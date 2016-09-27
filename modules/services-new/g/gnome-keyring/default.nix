{ config, lib, pkgs, ... }:

let
  inherit (lib)
    mkIf
    mkOption
    types;
in

{
  options = {

    services.gnome-keyring = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable GNOME Keyring daemon, a service designed to take
          care of the user's security credentials, such as user names and
          passwords.
        '';
      };

    };

  };

  config = mkIf config.services.gnome-keyring.enable {

    environment.systemPackages = [
      pkgs.gnome-keyring
    ];

    services.dbus.packages = [
      pkgs.gnome-keyring
    ];

  };
}
