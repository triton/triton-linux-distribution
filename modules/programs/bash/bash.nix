# This module defines global configuration for the Bash shell, in
# particular /etc/bashrc and /etc/profile.

{ config, pkgs, ... }:

with pkgs.lib;

let

  initBashCompletion = optionalString config.environment.enableBashCompletion ''
    # Check whether we're running a version of Bash that has support for
    # programmable completion. If we do, enable all modules installed in
    # the system (and user profile).
    if shopt -q progcomp &>/dev/null; then
      . "${pkgs.bashCompletion}/etc/profile.d/bash_completion.sh"
      nullglobStatus=$(shopt -p nullglob)
      shopt -s nullglob
      for p in $NIX_PROFILES; do
        for m in "$p/etc/bash_completion.d/"*; do
          . $m
        done
      done
      eval "$nullglobStatus"
      unset nullglobStatus p m
    fi
  '';

  options = {

    environment.promptInit =  mkOption {
      default = ''
        # Provide a nice prompt.
        PROMPT_COLOR="1;31m"
        let $UID && PROMPT_COLOR="1;32m"
        PS1="\n\[\033[$PROMPT_COLOR\][\u@\h:\w]\\$\[\033[0m\] "
        if test "$TERM" = "xterm"; then
          PS1="\[\033]2;\h:\u:\w\007\]$PS1"
        fi
      '';
      description = "
        Script used to initialized shell prompt.
      ";
      type = with pkgs.lib.types; string;
    };

    environment.shellInit = mkOption {
      default = "";
      example = ''export PATH=/godi/bin/:$PATH'';
      description = "
        Script used to initialized user shell environments.
      ";
      type = with pkgs.lib.types; string;
    };

    environment.enableBashCompletion = mkOption {
      default = false;
      description = "Enable bash-completion for all interactive shells.";
      type = with pkgs.lib.types; bool;
    };

    environment.binsh = mkOption {
      default = "${config.system.build.binsh}/bin/sh";
      example = "\${pkgs.dash}/bin/dash";
      type = with pkgs.lib.types; path;
      description = ''
        Select the shell executable that is linked system-wide to
        <literal>/bin/sh</literal>. Please note that NixOS assumes all
        over the place that shell to be Bash, so override the default
        setting only if you know exactly what you're doing.
      '';
    };

  };

in

{
  require = [options];

  environment.etc =
    [ { # Script executed when the shell starts as a login shell.
        source = pkgs.substituteAll {
          src = ./profile.sh;
          wrapperDir = config.security.wrapperDir;
          shellInit = config.environment.shellInit;
        };
        target = "profile";
      }

      { # /etc/bashrc: executed every time a bash starts. Sources
        # /etc/profile to ensure that the system environment is
        # configured properly.
         source = pkgs.substituteAll {
           src = ./bashrc.sh;
           inherit (config.environment) promptInit;
           inherit initBashCompletion;
         };
         target = "bashrc";
      }

      { # Configuration for readline in bash.
        source = ./inputrc;
        target = "inputrc";
      }
    ];

  system.build.binsh = pkgs.bashInteractive;

  system.activationScripts.binsh = stringAfter [ "stdio" ]
    ''
      # Create the required /bin/sh symlink; otherwise lots of things
      # (notably the system() function) won't work.
      mkdir -m 0755 -p /bin
      ln -sfn "${config.environment.binsh}" /bin/.sh.tmp
      mv /bin/.sh.tmp /bin/sh # atomically replace /bin/sh
    '';

  environment.pathsToLink = optional config.environment.enableBashCompletion "/etc/bash_completion.d";
}
