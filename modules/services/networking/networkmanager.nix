{ config, lib, pkgs, ... }:

with {
  inherit (lib)
    concatStrings
    concatStringsSep
    mkIf
    mkOption
    optionals
    optionalString
    types;
};

let
  cfg = config.networking.networkmanager;

  stateDirs = [
    "/var/lib/NetworkManager"
    "/var/lib/dhclient"
    "/var/lib/misc"  # dnsmasq leases
  ];

  configFile = pkgs.writeText "NetworkManager.conf" ''
    [main]
    dhcp=${cfg.dhcp-client}
    dns=${cfg.dns}
    plugins=keyfile
    rc-manager=${cfg.rc-manager}

    [keyfile]
    ${optionalString (config.networking.hostName != "")
      ''hostname=${config.networking.hostName}''}
    ${optionalString (cfg.unmanaged != [])
      ''unmanaged-devices=${concatStringsSep ";" cfg.unmanaged}''}

    [logging]
    level=WARN
  '';

  /*
    [network-manager]
    Identity=unix-group:networkmanager
    Action=org.freedesktop.NetworkManager.*
    ResultAny=yes
    ResultInactive=no
    ResultActive=yes

    [modem-manager]
    Identity=unix-group:networkmanager
    Action=org.freedesktop.ModemManager*
    ResultAny=yes
    ResultInactive=no
    ResultActive=yes
  */
  polkitConf = ''
    polkit.addRule(function(action, subject) {
      if (
        subject.isInGroup("networkmanager")
        && (action.id.indexOf("org.freedesktop.NetworkManager.") == 0
            || action.id.indexOf("org.freedesktop.ModemManager")  == 0
        ))
          { return polkit.Result.YES; }
    });
  '';

  ipUpScript = pkgs.writeScript "01-nixos-network-online" ''
    #!/bin/sh
    if test "$2" = "up"; then
      ${config.systemd.package}/bin/systemctl start network-online.target
    fi
  '';

  ns = xs: pkgs.writeText "nameservers" (
    concatStrings (map (s: "nameserver ${s}\n") xs)
  );

  overrideNameserversScript = pkgs.writeScript "02-override-dns" ''
    #!/bin/sh
    tmp=`${pkgs.coreutils}/bin/mktemp`
    ${pkgs.gnused}/bin/sed '/nameserver /d' /etc/resolv.conf > $tmp
    ${pkgs.gnugrep}/bin/grep 'nameserver ' /etc/resolv.conf | \
      ${pkgs.gnugrep}/bin/grep -vf \
        ${ns (cfg.appendNameservers ++ cfg.insertNameservers)} > $tmp.ns
    ${optionalString (cfg.appendNameservers != [])
      "${pkgs.coreutils}/bin/cat $tmp $tmp.ns ${ns cfg.appendNameservers} \
        > /etc/resolv.conf"}
    ${optionalString (cfg.insertNameservers != [])
      "${pkgs.coreutils}/bin/cat $tmp ${ns cfg.insertNameservers} $tmp.ns \
        > /etc/resolv.conf"}
    ${pkgs.coreutils}/bin/rm -f $tmp $tmp.ns
  '';

  dispatcherTypesSubdirMap = {
    "basic" = "";
    "pre-up" = "pre-up.d/";
    "pre-down" = "pre-down.d/";
  };
in

{

  options = {

    networking.networkmanager = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to use NetworkManager to obtain an IP address and other
          configuration for all network interfaces that are not manually
          configured. If enabled, a group `networkmanager` will be created.
          Add all users that should have permission to change network
          settings to this group.
        '';
      };

      dhcp-client = mkOption {
        type = types.enum [
          "dhclient"
          "dhcpcd"
          "internal"
        ];
        default = pkgs.networkmanager.dhcp-client;
      };

      dns = mkOption {
        type = types.enum [
          "default"
          "dnsmasq"
          # If /etc/resolv.conf is symlinked to /run/systemd/resolve/resolv.conf
          # this option is used automatically.
          "systemd-resolved"
          "unbound"
          "none"
        ];
        default = "default";
      };

      rc-manager = mkOption {
        type = types.enum [
          "symlink"
          "file"
          "resolvconf"
          "netconfig"
          "unmanaged"
        ];
        default = "symlink";
      };

      unmanaged = mkOption {
        type = types.listOf types.string;
        default = [ ];
        description = ''
          List of interfaces that will not be managed by NetworkManager.
          Interface name can be specified here, but if you need more fidelity
          see "Device List Format" in NetworkManager.conf man page.
        '';
      };

      # Ugly hack for using the correct gnome3 packageSet
      basePackages = mkOption {
        type = types.listOf types.package;
        default = [
          pkgs.networkmanager
          pkgs.modemmanager
          pkgs.networkmanager-l2tp
          pkgs.networkmanager-openconnect
          pkgs.networkmanager-openvpn
          pkgs.networkmanager-pptp
          pkgs.networkmanager-vpnc
          pkgs.wpa_supplicant
        ];
        internal = true;
      };

      packages = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = ''
          Extra packages that provide NetworkManager plugins.
        '';
        apply = list: (cfg.basePackages) ++ list;
      };

      appendNameservers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          A list of name servers that should be appended
          to the ones configured in NetworkManager or received by DHCP.
        '';
      };

      insertNameservers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          A list of name servers that should be inserted before
          the ones configured in NetworkManager or received by DHCP.
        '';
      };

      dispatcherScripts = mkOption {
        type = types.listOf (types.submodule {
          options = {
            source = mkOption {
              type = types.str;
              description = ''
                A script source.
              '';
            };

            type = mkOption {
              type = types.enum (attrNames dispatcherTypesSubdirMap);
              default = "basic";
              description = ''
                Dispatcher hook type. Only basic hooks are currently available.
              '';
            };
          };
        });
        default = [ ];
        description = ''
          A list of scripts which will be executed in response to  network
          events.
        '';
      };
    };
  };


  ###### implementation

  config = mkIf cfg.enable {

    assertions = [{
      assertion = config.networking.wireless.enable == false;
      message = "You can not use networking.networkmanager with "
        + "services.networking.wireless";
    }];

    boot.kernelModules = [
      # Needed for most (all?) PPTP VPN connections.
      "ppp_mppe"
    ];

    environment.etc = [
      {
        source = ipUpScript;
        target = "NetworkManager/dispatcher.d/01-nixos-network-online";
      }
      {
        source = configFile;
        target = "NetworkManager/NetworkManager.conf";
      }
      {
        source = "${pkgs.networkmanager-openvpn}/etc/NetworkManager/VPN/"
          + "nm-openvpn-service.name";
        target = "NetworkManager/VPN/nm-openvpn-service.name";
      }
      {
        source = "${pkgs.networkmanager-vpnc}/etc/NetworkManager/VPN/"
          + "nm-vpnc-service.name";
        target = "NetworkManager/VPN/nm-vpnc-service.name";
      }
      {
        source = "${pkgs.networkmanager-openconnect}/etc/NetworkManager/VPN/"
          + "nm-openconnect-service.name";
        target = "NetworkManager/VPN/nm-openconnect-service.name";
      }
      {
        source = "${pkgs.networkmanager-pptp}/etc/NetworkManager/VPN/"
          + "nm-pptp-service.name";
        target = "NetworkManager/VPN/nm-pptp-service.name";
      }
      {
        source = "${pkgs.networkmanager-l2tp}/etc/NetworkManager/VPN/"
          + "nm-l2tp-service.name";
        target = "NetworkManager/VPN/nm-l2tp-service.name";
      }
    ] ++ optionals (cfg.appendNameservers == [] || cfg.insertNameservers == []) [
      {
        source = overrideNameserversScript;
        target = "NetworkManager/dispatcher.d/02-override-dns";
      }
    ] ++ lib.imap (i: s: {
        text = s.source;
        target = "NetworkManager/dispatcher.d/"
          + "${dispatcherTypesSubdirMap.${s.type}}03-userscript${lib.fixedWidthNumber 4 i}";
      }) cfg.dispatcherScripts;

    environment.systemPackages = cfg.packages;

    users.extraGroups = [{
      name = "networkmanager";
      gid = config.ids.gids.networkmanager;
    }
    {
      name = "nm-openvpn";
      gid = config.ids.gids.nm-openvpn;
    }];
    users.extraUsers = [{
      name = "nm-openvpn";
      uid = config.ids.uids.nm-openvpn;
    }];

    systemd.packages = cfg.packages;

    # Create an initialisation service that both starts
    # NetworkManager when network.target is reached,
    # and sets up necessary directories for NM.
    systemd.services."networkmanager-init" = {
      description = "NetworkManager initialisation";
      wantedBy = [ "network.target" ];
      wants = [ "NetworkManager.service" ];
      before = [ "NetworkManager.service" ];
      script = ''
        mkdir -m 700 -p /etc/NetworkManager/system-connections
        mkdir -m 755 -p ${concatStringsSep " " stateDirs}
      '';
      serviceConfig.Type = "oneshot";
    };

    # Turn off NixOS' network management
    networking = {
      #useDHCP = false;
      wireless.enable = false;
    };

    powerManagement.resumeCommands = ''
      ${config.systemd.package}/bin/systemctl restart NetworkManager
    '';

    security.polkit.extraConfig = polkitConf;

    services.dbus.packages = cfg.packages;

    services.udev.packages = cfg.packages;
  };
}
