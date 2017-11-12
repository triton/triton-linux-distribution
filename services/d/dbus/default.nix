# D-Bus configuration and system bus daemon.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dbus;

  homeDir = "/var/run/dbus";

  systemExtraxml = concatStrings (flip concatMap cfg.packages (d: [
    "<servicedir>${d}/share/dbus-1/system-services</servicedir>"
    "<includedir>${d}/etc/dbus-1/system.d</includedir>"
  ]));

  sessionExtraxml = concatStrings (flip concatMap cfg.packages (d: [
    "<servicedir>${d}/share/dbus-1/services</servicedir>"
    "<includedir>${d}/etc/dbus-1/session.d</includedir>"
  ]));

  configDir = pkgs.stdenv.mkDerivation {
    name = "dbus-conf";

    preferLocalBuild = true;
    allowSubstitutes = false;

    buildCommand = ''
      mkdir -p $out

      sed '${./dbus-system-local.conf.in}' \
        -e 's,@servicehelper@,${config.security.wrapperDir}/dbus-daemon-launch-helper,g' \
        -e 's,@extra@,${systemExtraxml},' \
        > "$out/system-local.conf"

      sed '${./dbus-session-local.conf.in}' \
        -e 's,@extra@,${sessionExtraxml},' \
        > "$out/session-local.conf"
    '';
  };
in

{

  ###### interface

  options = {

    services.dbus = {

      enable = mkOption {
        type = types.bool;
        default = false;
        internal = true;
        description = ''
          Whether to start the D-Bus message bus daemon, which is
          required by many other system services and applications.
        '';
      };

      packages = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = ''
          Packages whose D-Bus configuration files should be included in
          the configuration of the D-Bus system-wide message bus.
          Specifically, every file in
          <filename><replaceable>pkg</replaceable>/etc/dbus-1/system.d</filename>
          is included.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    environment.etc = singleton {
      source = configDir;
      target = "dbus-1";
    };

    environment.pathsToLink = [
      "/etc/dbus-1"
      "/share/dbus-1"
    ];

    environment.systemPackages = [
      pkgs.dbus
    ];

    users.extraUsers.messagebus = {
      uid = config.ids.uids.messagebus;
      description = "D-Bus system message bus daemon user";
      home = homeDir;
      group = "messagebus";
    };

    users.extraGroups.messagebus.gid = config.ids.gids.messagebus;

    systemd.packages = [ pkgs.dbus ];

    security.setuidOwners = singleton {
      program = "dbus-daemon-launch-helper";
      source = "${pkgs.dbus}/libexec/dbus-daemon-launch-helper";
      owner = "root";
      group = "messagebus";
      setuid = true;
      setgid = false;
      permissions = "u+rx,g+rx,o-rx";
    };

    services.dbus.packages = [
      pkgs.dbus
      config.system.path
    ];

    # Don't restart dbus-daemon. Bad things tend to happen if we do.
    systemd.services.dbus.reloadIfChanged = true;

    systemd.services.dbus.restartTriggers = [ configDir ];

    # Fix the lack of directory prior to /var/lib/dbus/machine-id creation
    systemd.tmpfiles.rules = [
      "d /var/lib/dbus 0755 root root -"
    ];

    systemd.user = {
      services.dbus = {
        description = "D-Bus User Message Bus";
        requires = [ "dbus.socket" ];
        # NixOS doesn't support "Also" so we pull it in manually
        # As the .service is supposed to come up at the same time as
        # the .socket, we use basic.target instead of default.target
        wantedBy = [ "basic.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.dbus}/bin/dbus-daemon --session --address=systemd: --nofork --nopidfile --systemd-activation";
          ExecReload = "${pkgs.dbus}/bin/dbus-send --print-reply --session --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig";
        };
      };

      sockets.dbus = {
        description = "D-Bus User Message Bus Socket";
        socketConfig = {
          ListenStream = "%t/bus";
          ExecStartPost = "-${config.systemd.package}/bin/systemctl --user set-environment DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus";
        };
        wantedBy = [ "sockets.target" ];
      };
    };
  };
}
