{ config, lib, pkgs, ... }:

with lib;

let

  smbToString = x: if builtins.typeOf x == "bool"
                   then (if x then "true" else "false")
                   else toString x;

  cfg = config.services.samba;

  samba = cfg.package;

  setupScript =
    ''
      mkdir -p /var/lock/samba /var/log/samba /var/cache/samba /var/lib/samba/private
    '';

  shareConfig = name:
    let share = getAttr name cfg.shares; in
    "[${name}]\n " + (smbToString (
       map
         (key: "${key} = ${smbToString (getAttr key share)}\n")
         (attrNames share)
    ));

  configFile = pkgs.writeText "smb.conf"
    (if cfg.configText != null then cfg.configText else
    ''
      [ global ]
      security = ${cfg.securityType}
      passwd program = /var/setuid-wrappers/passwd %u
      invalid users = ${smbToString cfg.invalidUsers}

      ${cfg.extraConfig}

      ${smbToString (map shareConfig (attrNames cfg.shares))}
    '');

  daemonService = appName:
    { description = "Samba Service Daemon ${appName}";

      requiredBy = [ "samba.target" ];
      partOf = [ "samba.target" ];

      environment = {
        LOCALE_ARCHIVE = "/run/current-system/sw/lib/locale/locale-archive";
      };

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${samba}/sbin/${appName} --foreground --no-process-group";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
      };

      restartTriggers = [ configFile ];
    };

in

{

  ###### interface

  options = {

    # !!! clean up the descriptions.

    services.samba = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable Samba, which provides file and print
          services to Windows clients through the SMB/CIFS protocol.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.samba_full;
        defaultText = "pkgs.samba_full";
        description = ''
          Defines which package should be used for the samba server.
        '';
      };

      invalidUsers = mkOption {
        type = types.listOf types.str;
        default = [ "root" ];
        description = ''
          List of users who are denied to login via Samba.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Additional global section and extra section lines go in here.
        '';
      };

      configText = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = ''
          Verbatim contents of smb.conf. If null (default), use the
          autogenerated file from NixOS instead.
        '';
      };

      securityType = mkOption {
        type = types.str;
        default = "user";
        example = "share";
        description = "Samba security type";
      };

      nsswins = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to enable the WINS NSS (Name Service Switch) plug-in.
          Enabling it allows applications to resolve WINS/NetBIOS names (a.k.a.
          Windows machine names) by transparently querying the winbindd daemon.
        '';
      };

      shares = mkOption {
        default = {};
        description = ''
          A set describing shared resources.
          See <command>man smb.conf</command> for options.
        '';
        type = types.attrsOf (types.attrsOf types.unspecified);
        example =
          { srv =
             { path = "/srv";
               "read only" = true;
                comment = "Public samba share.";
             };
          };
      };

    };

  };


  ###### implementation

  config = mkMerge
    [ { # Always provide a smb.conf to shut up programs like smbclient and smbspool.
        environment.etc = singleton
          { source =
              if cfg.enable then configFile
              else pkgs.writeText "smb-dummy.conf" "# Samba is disabled.";
            target = "samba/smb.conf";
          };
      }

      (mkIf config.services.samba.enable {

        system.nssModules = optional cfg.nsswins samba;

        systemd = {
          targets.samba = {
            description = "Samba Server";
            requires = [ "samba-setup.service" ];
            after = [ "samba-setup.service" "network.target" ];
            wantedBy = [ "multi-user.target" ];
          };

          services = {
            "samba-nmbd" = daemonService "nmbd";
            "samba-smbd" = daemonService "smbd";
            "samba-winbindd" = daemonService "winbindd";
            "samba-setup" = {
              description = "Samba Setup Task";
              script = setupScript;
              unitConfig.RequiresMountsFor = "/var/lib/samba";
            };
          };
        };

        security.pam.services.samba = {};

      })
    ];

}
