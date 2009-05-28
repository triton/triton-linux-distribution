# This module defines global configuration for the Bash shell, in
# particular /etc/bashrc and /etc/profile.

{config, pkgs, ...}:

{
  environment.etc =
    [ { # /etc/bashrc: script executed when the shell starts as a
        # non-login shell.  /etc/profile also sources this file, so
        # most global configuration (such as environment variables)
        # should go into this script.
        source = pkgs.substituteAll {
          src = ./bashrc.sh;
          systemPath = config.system.path;
          wrapperDir = config.security.wrapperDir;
          modulesTree = config.system.modulesTree;
          defaultLocale = config.i18n.defaultLocale;
          nixEnvVars = config.nix.envVars;
          shellInit = config.environment.shellInit;
        };
        target = "bashrc";      
      }

      { # Script executed when the shell starts as a login shell.
        source = ./profile.sh;
        target = "profile";
      }

      { # Template for ~/.bashrc: script executed when the shell
        # starts as a non-login shell.
        source = ./bashrc-user.sh;
        target = "skel/.bashrc";
      }
      
      { # Configuration for readline in bash.
        source = ./inputrc;
        target = "inputrc";
      }
    ];

  system.build.binsh = pkgs.bashInteractive;
}
