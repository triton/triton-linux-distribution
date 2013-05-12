{ config, pkgs, ...}:
let
  cfg = config.services.varnish;
in
with pkgs.lib;
{
  options = {
    services.varnish = {
      enable = mkOption {
        default = false;
        description = "
          Enable the Varnish Server.
        ";
      };

      config = mkOption {
        description = "
          Verbatim default.vcl configuration.
        ";
      };

      stateDir = mkOption {
        default = "/var/spool/varnish";
        description = "
          Directory holding all state for Varnish to run.
        ";
      };
    };

  };

  config = mkIf cfg.enable {

    systemd.services.varnish = {
      description = "Varnish";
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        mkdir -p ${cfg.stateDir}
        chown -R varnish:varnish ${cfg.stateDir}
      '';
      path = [ pkgs.gcc ];
      serviceConfig.ExecStart = "${pkgs.varnish}/sbin/varnishd -f ${pkgs.writeText "default.vcl" cfg.config} -n ${cfg.stateDir} -u varnish";
      serviceConfig.Type = "forking";
    };

    environment.systemPackages = [ pkgs.varnish ];

    users.extraUsers.varnish = {
      group = "varnish";
    };

    users.extraGroups.varnish = {};
  };
}
