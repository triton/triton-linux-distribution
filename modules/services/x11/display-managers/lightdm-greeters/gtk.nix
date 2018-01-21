{ config, lib, pkgs, ... }:

with lib;

let

  dmcfg = config.services.xserver.displayManager;
  ldmcfg = dmcfg.lightdm;
  cfg = ldmcfg.greeters.gtk;

  inherit (pkgs) stdenv lightdm writeScript writeText;

  theme = cfg.theme.package;
  icons = cfg.iconTheme.package;

  # The default greeter provided with this expression is the GTK greeter.
  # Again, we need a few things in the environment for the greeter to run with
  # fonts/icons.
  wrappedGtkGreeter = stdenv.mkDerivation {
    name = "lightdm-gtk-greeter";
    buildInputs = [ pkgs.makeWrapper ];

    buildCommand = ''
      # This wrapper ensures that we actually get themes
      makeWrapper ${pkgs.lightdm-gtk-greeter}/sbin/lightdm-gtk-greeter \
        $out/greeter \
        --prefix PATH : "${pkgs.glibc}/bin" \
        --set GTK_PATH "${theme}:${pkgs.gtk3}" \
        --set GTK_EXE_PREFIX "${theme}" \
        --set GTK_DATA_PREFIX "${theme}" \
        --set XDG_DATA_DIRS "${theme}/share:${icons}/share" \
        --set XDG_CONFIG_HOME "${theme}/share"

      cat - > $out/lightdm-gtk-greeter.desktop << EOF
      [Desktop Entry]
      Name=LightDM Greeter
      Comment=This runs the LightDM Greeter
      Exec=$out/greeter
      Type=Application
      EOF
    '';
  };

  gtkGreeterConf = writeText "lightdm-gtk-greeter.conf"
    ''
    [greeter]
    theme-name = ${cfg.theme.name}
    icon-theme-name = ${cfg.iconTheme.name}
    background = ${ldmcfg.background}
    indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power;~
    '';

in
{
  options = {

    services.xserver.displayManager.lightdm.greeters.gtk = {

      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable lightdm-gtk-greeter as the lightdm greeter.
        '';
      };

      theme = {

        package = mkOption {
          type = types.package;
          default = pkgs.gnome-themes-standard;
          defaultText = "pkgs.gnome-themes-standard";
          description = ''
            The package path that contains the theme given in the name option.
          '';
        };

        name = mkOption {
          type = types.str;
          default = "Adwaita";
          description = ''
            Name of the theme to use for the lightdm-gtk-greeter.
          '';
        };

      };

      iconTheme = {

        package = mkOption {
          type = types.package;
          default = pkgs.adwaita-icon-theme;
          defaultText = "pkgs.adwaita-icon-theme";
          description = ''
            The package path that contains the icon theme given in the name option.
          '';
        };

        name = mkOption {
          type = types.str;
          default = "Adwaita";
          description = ''
            Name of the icon theme to use for the lightdm-gtk-greeter.
          '';
        };

      };

    };

  };

  config = mkIf (ldmcfg.enable && cfg.enable) {

    services.xserver.displayManager.lightdm.greeter = mkDefault {
      package = wrappedGtkGreeter;
      name = "lightdm-gtk-greeter";
    };

    environment.etc."lightdm/lightdm-gtk-greeter.conf".source = gtkGreeterConf;

  };
}
