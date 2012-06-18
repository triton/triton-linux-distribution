{ config, pkgs, ... }:

with pkgs.lib;

{

  ###### interface

  options = {

    services.mingetty = {

      # FIXME
      ttys = mkOption {
        default =
          if pkgs.stdenv.isArm
          then [ "ttyS0" ] # presumably an embedded platform such as a plug
          else [ "tty1" "tty2" "tty3" "tty4" "tty5" "tty6" ];
        description = ''
          The list of tty devices on which to start a login prompt.
        '';
      };

      waitOnMounts = mkOption {
        default = false;
        description = ''
          Whether the login prompts on the virtual consoles will be
          started before or after all file systems have been mounted.  By
          default we don't wait, but if for example your /home is on a
          separate partition, you may want to turn this on.
        '';
      };

      greetingLine = mkOption {
        default = ''<<< Welcome to NixOS ${config.system.nixosVersion} (\m) - \l >>>'';
        description = ''
          Welcome line printed by mingetty.
        '';
      };

      helpLine = mkOption {
        default = "";
        description = ''
          Help line printed by mingetty below the welcome line.
          Used by the installation CD to give some hints on
          how to proceed.
        '';
      };

    };

  };


  ###### implementation

  config = {

    # Generate a separate job for each tty.
    boot.systemd.units."getty@.service".text =
      ''
        [Unit]
        Description=Getty on %I
        Documentation=man:agetty(8)
        After=systemd-user-sessions.service plymouth-quit-wait.service

        # If additional gettys are spawned during boot then we should make
        # sure that this is synchronized before getty.target, even though
        # getty.target didn't actually pull it in.
        Before=getty.target
        IgnoreOnIsolate=yes

        [Service]
        Environment=TERM=linux
        Environment=LOCALE_ARCHIVE=/var/run/current-system/sw/lib/locale/locale-archive
        ExecStart=@${pkgs.utillinux}/sbin/agetty agetty --noclear --login-program ${pkgs.shadow}/bin/login %I 38400
        Type=idle
        Restart=always
        RestartSec=0
        UtmpIdentifier=%I
        TTYPath=/dev/%I
        TTYReset=yes
        TTYVHangup=yes
        TTYVTDisallocate=yes
        KillMode=process
        IgnoreSIGPIPE=no

        # Some login implementations ignore SIGTERM, so we send SIGHUP
        # instead, to ensure that login terminates cleanly.
        KillSignal=SIGHUP
      '';
    
    environment.etc = singleton
      { # Friendly greeting on the virtual consoles.
        source = pkgs.writeText "issue" ''

          [1;32m${config.services.mingetty.greetingLine}[0m
          ${config.services.mingetty.helpLine}

        '';
        target = "issue";
      };

  };

}
