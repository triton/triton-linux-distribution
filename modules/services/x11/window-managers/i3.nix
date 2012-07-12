{pkgs, config, ...}:

let
  inherit (pkgs.lib) mkOption mkIf;
  cfg = config.services.xserver.windowManager.i3;
in

{
  options = {
    services.xserver.windowManager.i3 = {
      enable = mkOption {
        default = false;
        example = true;
        description = "Enable the i3 tiling window manager.";
      };
    };
  };

  config = mkIf cfg.enable {
    services.xserver.windowManager = {
      session = [{
        name = "i3";
        start = "
          ${pkgs.i3}/bin/i3 &
          waitPID=$!
        ";
      }];
    };
    environment.x11Packages = [ pkgs.i3 ];
  };
}
