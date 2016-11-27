{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.plex-media-server;
  plex = pkgs.plex-media-server;
in
{
  options = {
    services.plex-media-server = {
      enable = mkEnableOption "Plex Media Server";

      user = mkOption {
        type = types.str;
        default = "plex";
        description = "User account under which Plex runs.";
      };

      group = mkOption {
        type = types.str;
        default = "plex";
        description = "Group under which Plex runs.";
      };

      managePlugins = mkOption {
        type = types.bool;
        default = false;
        description = ''
          If set to true, this option will cause all of the symlinks in Plex's
          plugin directory to be removed and symlinks for paths specified in
          <option>extraPlugins</option> to be added.
        '';
      };

      extraPlugins = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = ''
          A list of paths to extra plugin bundles to install in Plex's plugin
          directory. Every time the systemd unit for Plex starts up, all of the
          symlinks in Plex's plugin directory will be cleared and this module
          will symlink all of the paths specified here to that directory. If
          this behavior is undesired, set <option>managePlugins</option> to
          false.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.plex-media-server;
        defaultText = "pkgs.plex-media-server";
        description = ''
          The Plex package to use. Plex subscribers may wish to use their own
          package here, pointing to subscriber-only server versions.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    # Most of this is just copied from the RPM package's systemd service file.
    systemd.services.plex = {
      description = "Plex Media Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        if [ ! -d "${cfg.package.dataDir}" ] ; then
          mkdir -pv '${cfg.package.dataDir}/Plex Media Server'
          chown -R ${cfg.user}:${cfg.group} '${cfg.package.dataDir}'
        fi

        # Copy the database skeleton files to /var/lib/plex/.skeleton
        plexDb='com.plexapp.plugins.library.db'
        plexDbBase="${cfg.package}/lib/plexmediaserver/Resources/base_$plexDb"
        plexDbTargetDir="${cfg.package.dataDir}/.skeleton"
        plexDbTarget="$plexDbTargetDir/$plexDb"
        if [ ! -f "$plexDbTarget" ] ; then
          if [ ! -d "#plexDbTargetDir" ] ; then
            mkdir -pv "$plexDbTargetDir"
          fi
          cp -v "$plexDbBase" "$plexDbTarget"
          chmod u+w "${cfg.package.dataDir}/.skeleton/$db"
          chown ${cfg.user}:${cfg.group} "$plexDbTarget"
        fi
      '' /* If managePlugins is enabled, setup symlinks for plugins. */
        + optionalString cfg.managePlugins ''
        echo "Preparing plugin directory."
        PLUGINDIR="${cfg.package.dataDir}/Plex Media Server/Plug-ins"
        test -d "$PLUGINDIR" || {
          mkdir -p "$PLUGINDIR";
          chown ${cfg.user}:${cfg.group} "$PLUGINDIR";
        }

        echo "Removing old symlinks."
        # First, remove all of the symlinks in the directory.
        for f in `ls "$PLUGINDIR/"` ; do
          if [ -L "$PLUGINDIR/$f" ] ; then
            rm -v "$PLUGINDIR/$f"
          fi
        done

        echo "Symlinking plugins."
        for path in ${toString cfg.extraPlugins} ; do
          dest="$PLUGINDIR/$(basename $path)"
          if [ ! -d "$path" ] ; then
            echo "Error symlinking plugin from $path: no such directory."
          elif [ -d "$dest" ] || [ -L "$dest" ] ; then
            echo "Error symlinking plugin from $path to $dest: file or directory already exists."
          else
            echo "Symlinking plugin at $path..."
            ln -sv "$path" "$dest"
          fi
        done
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        PermissionsStartOnly = "true";
        ExecStart = "/bin/sh -c '${cfg.package}/lib/plexmediaserver/Plex\\ Media\\ Server'";
      };
      environment = {
        PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=cfg.package.dataDir;
        PLEX_MEDIA_SERVER_HOME="${cfg.package}/lib/plexmediaserver";
        PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS="6";
        PLEX_MEDIA_SERVER_TMPDIR="/tmp";
        LD_LIBRARY_PATH = "${plex.libraryPath}:${cfg.package.dataDir}";
        LC_ALL="en_US.UTF-8";
        LANG="en_US.UTF-8";
      };
    };

    users.extraUsers = mkIf (cfg.user == "plex") {
      plex = {
        group = cfg.group;
        uid = config.ids.uids.plex;
      };
    };

    users.extraGroups = mkIf (cfg.group == "plex") {
      plex = {
        gid = config.ids.gids.plex;
      };
    };
  };
}
