{ config, pkgs, ... }:

with pkgs.lib;

{

  ###### interface

  options = {

    swapDevices = mkOption {
      default = [];
      example = [
        { device = "/dev/hda7"; }
        { device = "/var/swapfile"; }
        { label = "bigswap"; }
      ];
      description = ''
        The swap devices and swap files.  These must have been
        initialised using <command>mkswap</command>.  Each element
        should be an attribute set specifying either the path of the
        swap device or file (<literal>device</literal>) or the label
        of the swap device (<literal>label</literal>, see
        <command>mkswap -L</command>).  Using a label is
        recommended.
      '';

      type = types.list types.optionSet;

      options = {config, options, ...}: {

        options = {

          device = mkOption {
            example = "/dev/sda3";
            type = types.uniq types.string;
            description = "Path of the device.";
          };

          label = mkOption {
            example = "swap";
            type = types.uniq types.string;
            description = ''
              Label of the device.  Can be used instead of <varname>device</varname>.
            '';
          };

          size = mkOption {
            default = null;
            example = 2048;
            type = types.nullOr types.int;
            description = ''
              If this option is set, ‘device’ is interpreted as the
              path of a swapfile that will be created automatically
              with the indicated size (in megabytes) if it doesn't
              exist.
            '';
          };

        };

        config = {
          device =
            if options.label.isDefined then
              "/dev/disk/by-label/${config.label}"
            else
              mkNotdef;
        };

      };

    };

  };

  config = mkIf ((length config.swapDevices) != 0) {

    system.requiredKernelConfig = with config.lib.kernelConfig; [
      (isYes "SWAP")
    ];

    # Create missing swapfiles.
    # FIXME: support changing the size of existing swapfiles.
    boot.systemd.services =
      let

        escapePath = s: # FIXME: slow
          replaceChars ["/" "-"] ["-" "\\x2d"] (substring 1 (stringLength s) s);

        createSwapDevice = sw: assert sw.device != ""; nameValuePair "mkswap-${escapePath sw.device}"
          { description = "Initialisation of Swapfile ${sw.device}";
            wantedBy = [ "${escapePath sw.device}.swap" ];
            before = [ "${escapePath sw.device}.swap" ];
            path = [ pkgs.utillinux ];
            script =
              ''
                if [ ! -e "${sw.device}" ]; then
                  fallocate -l ${toString sw.size}M "${sw.device}" ||
                    dd if=/dev/zero of="${sw.device}" bs=1M count=${toString sw.size}
                  mkswap ${sw.device}
                fi
              '';
            unitConfig.RequiresMountsFor = "${dirOf sw.device}";
            unitConfig.DefaultDependencies = false; # needed to prevent a cycle
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
          };

      in listToAttrs (map createSwapDevice (filter (sw: sw.size != null) config.swapDevices));

  };

}
