{ config, pkgs, ... }:

with pkgs.lib;

let

  cfg = config.services.spamassassin;

in

{

  ###### interface

  options = {

    services.spamassassin = {

      enable = mkOption {
        default = false;
        description = "Whether to run the SpamAssassin daemon.";
      };

    };

  };


  ###### implementation

  config = mkIf cfg.enable {

    # This makes comfortable for users to run 'spamassassin'.
    environment.systemPackages = [ pkgs.spamassassin ];

    jobs.spamd = {
      description = "Spam Assassin Server";
      startOn = "started networking and filesystem";
      environment.TZ = config.time.timeZone;
      exec = "spamd -C /etc/spamassassin/init.pre --siteconfigpath=/etc/spamassassin --debug --pidfile=/var/run/spamd.pid";
    };

  };

}
