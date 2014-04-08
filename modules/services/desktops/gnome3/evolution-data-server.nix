# Evolution Data Server daemon.

{ config, pkgs, ... }:

with pkgs.lib;

{

  ###### interface

  options = {

    services.gnome3.evolution-data-server = {

      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to enable Evolution Data Server, a collection of services for 
          storing addressbooks and calendars.
        '';
      };

    };

  };


  ###### implementation

  config = mkIf config.services.gnome3.evolution-data-server.enable {

    environment.systemPackages = [ pkgs.evolution_data_server ];

    services.dbus.packages = [ pkgs.evolution_data_server ];

  };

}
