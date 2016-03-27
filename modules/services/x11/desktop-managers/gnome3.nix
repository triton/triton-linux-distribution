{ config, lib, pkgs, ... }:

with {
  inherit (lib)
    concatMapStrings
    literalExample
    mkDefault
    mkIf
    mkOption
    singleton
    types;
};

let
  # Remove packages of ys from xs, based on their names
  removePackagesByName = xs: ys:
    let
      pkgName = drv: (builtins.parseDrvName drv.name).name;
      ysNames = map pkgName ys;
      res = (filter (x: !(builtins.elem (pkgName x) ysNames)) xs);
    in
      filter (x: !(builtins.elem (pkgName x) ysNames)) xs;

  # Prioritize nautilus by default when opening directories
  mimeAppsList = pkgs.writeTextFile {
    name = "gnome-mimeapps";
    destination = "/share/applications/mimeapps.list";
    text = ''
      [Default Applications]
      inode/directory=nautilus.desktop;org.gnome.Nautilus.desktop
    '';
  };

  nixos-gsettings-desktop-schemas = pkgs.stdenv.mkDerivation {
    name = "nixos-gsettings-desktop-schemas";
    buildInputs = [ pkgs.nixos-artwork ];
    buildCommand = ''
     mkdir -pv $out/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas
     cp -rvf \
       ${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas*/glib-2.0 \
       $out/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas/
     chmod -R a+w $out/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas
     cat - > $out/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas/glib-2.0/schemas/nixos-defaults.gschema.override <<- EOF
       [org.gnome.desktop.background]
       picture-uri='${pkgs.nixos-artwork}/share/artwork/gnome/Gnome_Dark.png'
       [org.gnome.desktop.screensaver]
       picture-uri='${pkgs.nixos-artwork}/share/artwork/gnome/Gnome_Dark.png'
     EOF
     ${pkgs.glib}/bin/glib-compile-schemas \
       $out/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas/glib-2.0/schemas/
    '';
  };

in {

  options = {

    services.xserver.desktopManager.gnome3 = {

      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = "Enable Gnome 3 desktop manager.";
      };

      sessionPath = mkOption {
        default = [ ];
        example = literalExample "[ pkgs.gnome3.gpaste ]";
        description = "Additional list of packages to be added to the session search path.
                       Useful for gnome shell extensions or gsettings-conditionated autostart.";
        apply = list: list ++ [
          pkgs.gnome-shell
          pkgs.gnome-shell-extensions
        ];
      };

    };

  };

  config = mkIf config.services.xserver.desktopManager.gnome3.enable {

    services.dconf.enable = true;

    security.polkit.enable = true;

    services.udisks.enable = true;

    services.accounts-daemon.enable = true;

    services.geoclue.enable = mkDefault true;

    services.at-spi2-core.enable = true;

    services.evolution-data-server.enable = true;

    #services.gnome-documents.enable = mkDefault true;

    services.gnome-keyring.enable = true;

    # Remove dependency on webkit
    #services.gnome-online-accounts.enable = mkDefault true;

    services.gnome-user-share.enable = mkDefault true;

    services.gvfs.enable = true;

    services.seahorse.enable = mkDefault true;

    # Remove dependency on webkit
    #services.sushi.enable = mkDefault true;

    services.tracker.enable = mkDefault true;

    hardware.pulseaudio.enable = mkDefault true;

    services.telepathy.enable = mkDefault true;

    networking.networkmanager.enable = mkDefault true;

    services.upower.enable = config.powerManagement.enable;

    hardware.bluetooth.enable = mkDefault true;

    fonts.fonts = [
      pkgs.dejavu_fonts
      pkgs.cantarell_fonts
    ];

    services.xserver.desktopManager.session = singleton {
      name = "gnome3";
      bgSupport = true;
      start =
        /* Set GTK_DATA_PREFIX so that GTK+ can find the themes */ ''
          export GTK_DATA_PREFIX=${config.system.path}
        '' + /* find theme engines */ ''
          export GTK_PATH=${config.system.path}/lib/gtk-3.0:${config.system.path}/lib/gtk-2.0

          export XDG_MENU_PREFIX=gnome

          ${concatMapStrings (p: ''
            if [ -d "${p}/share/gsettings-schemas/${p.name}" ]; then
              export XDG_DATA_DIRS=$XDG_DATA_DIRS''${XDG_DATA_DIRS:+:}${p}/share/gsettings-schemas/${p.name}
            fi

            if [ -d "${p}/lib/girepository-1.0" ]; then
              export GI_TYPELIB_PATH=$GI_TYPELIB_PATH''${GI_TYPELIB_PATH:+:}${p}/lib/girepository-1.0
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH''${LD_LIBRARY_PATH:+:}${p}/lib
            fi
          '') config.services.xserver.desktopManager.gnome3.sessionPath}
        '' + /* Override default mimeapps */ ''
          export XDG_DATA_DIRS=$XDG_DATA_DIRS''${XDG_DATA_DIRS:+:}${mimeAppsList}/share
        '' + /* Override gsettings-desktop-schema */ ''
          export XDG_DATA_DIRS=${nixos-gsettings-desktop-schemas}/share/nixos-gsettings-schemas/nixos-gsettings-desktop-schemas''${XDG_DATA_DIRS:+:}$XDG_DATA_DIRS
        '' + /* Let nautilus find extensions */ ''
          export NAUTILUS_EXTENSION_DIR=${config.system.path}/lib/nautilus/extensions-3.0/
        '' + /* Find the mouse */ ''
          export XCURSOR_PATH=~/.icons:${config.system.path}/share/icons
        '' + /* Update user dirs as described in
                http://freedesktop.org/wiki/Software/xdg-user-dirs/ */ ''
          ${pkgs.xdg-user-dirs}/bin/xdg-user-dirs-update

          ${pkgs.gnome-session}/bin/gnome-session&
          waitPID=$!
        '';
    };

    environment.systemPackages = [
      pkgs.adwaita-icon-theme
      pkgs.dconf
      pkgs.desktop_file_utils
      pkgs.glib
      pkgs.glib-networking
      pkgs.gnome-backgrounds
      pkgs.gnome-control-center
      pkgs.gnome-menus
      pkgs.gnome-settings-daemon
      pkgs.gnome-shell
      pkgs.gnome-shell-extensions
      pkgs.gnome-themes-standard
      pkgs.gtk3
      pkgs.gvfs
      pkgs.hicolor_icon_theme
      pkgs.ibus
      pkgs.shared_mime_info
    ] ++ config.services.xserver.desktopManager.gnome3.sessionPath;

    # Needed for themes and backgrounds
    environment.pathsToLink = [ "/share" ];

  };


}
