# Zabbix server daemon.
{ config, pkgs, ... }:

with pkgs.lib;

let

  stateDir = "/var/run/zabbix";

  logDir = "/var/log/zabbix";

  libDir = "/var/lib/zabbix";

  pidFile = "${stateDir}/zabbix_server.pid";

  configFile = pkgs.writeText "zabbix_server.conf"
    ''
      LogFile = ${logDir}/zabbix_server
  
      PidFile = ${pidFile}

      DBName = zabbix

      DBUser = zabbix
    '';

in
  
{

  ###### interface

  options = {
  
    services.zabbixServer.enable = mkOption {
      default = false;
      description = ''
        Whether to run the Zabbix server on this machine.
      '';
    };

  };

  ###### implementation

  config = mkIf config.services.zabbixServer.enable {

    services.postgresql.enable = true;

    users.extraUsers = singleton
      { name = "zabbix";
        uid = config.ids.uids.zabbix;
        description = "Zabbix daemon user";
      };

    jobs.zabbix_server =
      { name = "zabbix-server";

        description = "Zabbix server daemon";

        startOn = "started postgresql";
        stopOn = "stopping postgresql";

        preStart =
          ''
            mkdir -m 0755 -p ${stateDir} ${logDir} ${libDir}
            chown zabbix ${stateDir} ${logDir} ${libDir}

            if ! test -e "${libDir}/db-created"; then
                ${pkgs.postgresql}/bin/createuser --no-superuser --no-createdb --no-createrole zabbix || true
                ${pkgs.postgresql}/bin/createdb --owner zabbix zabbix || true
                cat ${pkgs.zabbix.server}/share/zabbix/db/schema/postgresql.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                cat ${pkgs.zabbix.server}/share/zabbix/db/data/data.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                cat ${pkgs.zabbix.server}/share/zabbix/db/data/images_pgsql.sql | ${pkgs.su}/bin/su -s "$SHELL" zabbix -c '${pkgs.postgresql}/bin/psql zabbix'
                touch "${libDir}/db-created"
            fi

            export PATH=${pkgs.nettools}/bin:$PATH
            ${pkgs.zabbix.server}/sbin/zabbix_server --config ${configFile}
          '';

        postStop =
          ''
            pid=$(cat ${pidFile})
            test -n "$pid" && kill "$pid"
            # Wait until they're really gone.
            while ${pkgs.procps}/bin/pkill -u zabbix zabbix_server; do true; done
          '';
      };
      
  };

}
