{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.boot.loader.grub;

  efi = config.boot.loader.efi;

  realGrub =
    if cfg.version == 1 then
      throw "Grub1 is not a thing anymore"
    else if cfg.trustedBoot.enable then
      throw "Trusted grub is not supported"
    else
      pkgs.grub_bios-i386;

  grub =
    # Don't include GRUB if we're only generating a GRUB menu (e.g.,
    # in EC2 instances).
    if cfg.devices == [ "nodev" ] then
      null
    else
      realGrub;

  grubEfi =
    # EFI version of Grub v2
    if cfg.efiSupport && (cfg.version == 2) then
      pkgs.grub_efi-x86_64
    else
      null;

  f = x: if x == null then "" else "" + x;

  grubConfig = args:
    let
      efiSysMountPoint = if args.efiSysMountPoint == null then args.path else args.efiSysMountPoint;
      efiSysMountPoint' = replaceChars [ "/" ] [ "-" ] efiSysMountPoint;
    in
    pkgs.writeText "grub-config.xml" (builtins.toXML
    { splashImage = f cfg.splashImage;
      grub = f grub;
      grubTarget = if grub != null then "${grub.target}-${grub.platform}" else "";
      shell = "${pkgs.stdenv.shell}";
      fullName = (builtins.parseDrvName realGrub.name).name;
      fullVersion = (builtins.parseDrvName realGrub.name).version;
      grubEfi = f grubEfi;
      fontTTF = f cfg.fontTTF;
      grubTargetEfi = if grubEfi != null then "${grubEfi.target}-${grubEfi.platform}" else "";
      bootPath = args.path;
      storePath = config.boot.loader.grub.storePath;
      bootloaderId = if args.efiBootloaderId == null then "NixOS${efiSysMountPoint'}" else args.efiBootloaderId;
      timeout = if config.boot.loader.timeout == null then -1 else config.boot.loader.timeout;
      inherit efiSysMountPoint;
      inherit (args) devices;
      inherit (efi) canTouchEfiVariables;
      inherit (cfg)
        version extraConfig extraPerEntryConfig extraEntries
        extraEntriesBeforeNixOS extraPrepareConfig configurationLimit copyKernels
        default fsIdentifier efiSupport gfxmodeEfi gfxmodeBios;
      path = (makeSearchPath "bin" ([
        pkgs.btrfs-progs
        pkgs.coreutils
        pkgs.diffutils
        pkgs.findutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.util-linux_full
        pkgs.xz
      ])) + ":" + (makeSearchPath "sbin" [
        pkgs.mdadm pkgs.util-linux_full
      ]);
    });

  bootDeviceCounters = fold (device: attr: attr // { "${device}" = (attr."${device}" or 0) + 1; }) {}
    (concatMap (args: args.devices) cfg.mirroredBoots);

in

{

  ###### interface

  options = {

    boot.loader.grub = {

      enable = mkOption {
        default = !config.boot.isContainer;
        type = types.bool;
        description = ''
          Whether to enable the GNU GRUB boot loader.
        '';
      };

      version = mkOption {
        default = 2;
        example = 1;
        type = types.int;
        description = ''
          The version of GRUB to use: <literal>1</literal> for GRUB
          Legacy (versions 0.9x), or <literal>2</literal> (the
          default) for GRUB 2.
        '';
      };

      device = mkOption {
        default = "";
        example = "/dev/hda";
        type = types.str;
        description = ''
          The device on which the GRUB boot loader will be installed.
          The special value <literal>nodev</literal> means that a GRUB
          boot menu will be generated, but GRUB itself will not
          actually be installed.  To install GRUB on multiple devices,
          use <literal>boot.loader.grub.devices</literal>.
        '';
      };

      devices = mkOption {
        default = [];
        example = [ "/dev/hda" ];
        type = types.listOf types.str;
        description = ''
          The devices on which the boot loader, GRUB, will be
          installed. Can be used instead of <literal>device</literal> to
          install GRUB onto multiple devices.
        '';
      };

      mirroredBoots = mkOption {
        default = [ ];
        example = [
          { path = "/boot1"; devices = [ "/dev/sda" ]; }
          { path = "/boot2"; devices = [ "/dev/sdb" ]; }
        ];
        description = ''
          Mirror the boot configuration to multiple partitions and install grub
          to the respective devices corresponding to those partitions.
        '';

        type = types.listOf types.optionSet;

        options = {

          path = mkOption {
            example = "/boot1";
            type = types.str;
            description = ''
              The path to the boot directory where GRUB will be written. Generally
              this boot path should double as an EFI path.
            '';
          };

          efiSysMountPoint = mkOption {
            default = null;
            example = "/boot1/efi";
            type = types.nullOr types.str;
            description = ''
              The path to the efi system mount point. Usually this is the same
              partition as the above path and can be left as null.
            '';
          };

          efiBootloaderId = mkOption {
            default = null;
            example = "NixOS-fsid";
            type = types.nullOr types.str;
            description = ''
              The id of the bootloader to store in efi nvram.
              The default is to name it NixOS and append the path or efiSysMountPoint.
              This is only used if <literal>boot.loader.efi.canTouchEfiVariables</literal> is true.
            '';
          };

          devices = mkOption {
            default = [ ];
            example = [ "/dev/sda" "/dev/sdb" ];
            type = types.listOf types.str;
            description = ''
              The path to the devices which will have the GRUB MBR written.
              Note these are typically device paths and not paths to partitions.
            '';
          };

        };
      };

      configurationName = mkOption {
        default = "";
        example = "Stable 2.6.21";
        type = types.str;
        description = ''
          GRUB entry name instead of default.
        '';
      };

      storePath = mkOption {
        default = "/nix/store";
        type = types.str;
        description = ''
          Path to the Nix store when looking for kernels at boot.
          Only makes sense when copyKernels is false.
        '';
      };

      extraPrepareConfig = mkOption {
        default = "";
        type = types.lines;
        description = ''
          Additional bash commands to be run at the script that
          prepares the GRUB menu entries.
        '';
      };

      extraConfig = mkOption {
        default = "";
        example = "serial; terminal_output.serial";
        type = types.lines;
        description = ''
          Additional GRUB commands inserted in the configuration file
          just before the menu entries.
        '';
      };

      extraPerEntryConfig = mkOption {
        default = "";
        example = "root (hd0)";
        type = types.lines;
        description = ''
          Additional GRUB commands inserted in the configuration file
          at the start of each NixOS menu entry.
        '';
      };

      extraEntries = mkOption {
        default = "";
        type = types.lines;
        example = ''
          # GRUB 1 example (not GRUB 2 compatible)
          title Windows
            chainloader (hd0,1)+1

          # GRUB 2 example
          menuentry "Windows 7" {
            chainloader (hd0,4)+1
          }
        '';
        description = ''
          Any additional entries you want added to the GRUB boot menu.
        '';
      };

      extraEntriesBeforeNixOS = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether extraEntries are included before the default option.
        '';
      };

      extraFiles = mkOption {
        type = types.attrsOf types.path;
        default = {};
        example = literalExample ''
          { "memtest.bin" = "''${pkgs.memtest86plus}/memtest.bin"; }
        '';
        description = ''
          A set of files to be copied to <filename>/boot</filename>.
          Each attribute name denotes the destination file name in
          <filename>/boot</filename>, while the corresponding
          attribute value specifies the source file.
        '';
      };

      splashImage = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExample "./my-background.png";
        description = ''
          Background image used for GRUB.  It must be a 640x480,
          14-colour image in XPM format, optionally compressed with
          <command>gzip</command> or <command>bzip2</command>.  Set to
          <literal>null</literal> to run GRUB in text mode.
        '';
      };

      fontTTF = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = literalExample "''${pkgs.dejavu-fonts}/share/fonts/truetype/DejaVuSans.ttf";
        description = ''
          The TTF file to use for the font in the grub graphical mode.
        '';
      };

      gfxmodeEfi = mkOption {
        default = "auto";
        example = "1024x768";
        type = types.str;
        description = ''
          The gfxmode to pass to GRUB when loading a graphical boot interface under EFI.
        '';
      };

      gfxmodeBios = mkOption {
        default = "1024x768";
        example = "auto";
        type = types.str;
        description = ''
          The gfxmode to pass to GRUB when loading a graphical boot interface under BIOS.
        '';
      };

      configurationLimit = mkOption {
        default = 100;
        example = 120;
        type = types.int;
        description = ''
          Maximum of configurations in boot menu. GRUB has problems when
          there are too many entries.
        '';
      };

      copyKernels = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether the GRUB menu builder should copy kernels and initial
          ramdisks to /boot.  This is done automatically if /boot is
          on a different partition than /.
        '';
      };

      default = mkOption {
        default = 0;
        type = types.int;
        description = ''
          Index of the default menu item to be booted.
        '';
      };

      fsIdentifier = mkOption {
        default = "uuid";
        type = types.addCheck types.str
          (type: type == "uuid" || type == "label" || type == "provided");
        description = ''
          Determines how GRUB will identify devices when generating the
          configuration file. A value of uuid / label signifies that grub
          will always resolve the uuid or label of the device before using
          it in the configuration. A value of provided means that GRUB will
          use the device name as show in <command>df</command> or
          <command>mount</command>. Note, zfs zpools / datasets are ignored
          and will always be mounted using their labels.
        '';
      };

      zfsSupport = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether GRUB should be build against libzfs.
          ZFS support is only available for GRUB v2.
          This option is ignored for GRUB v1.
        '';
      };

      efiSupport = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether GRUB should be build with EFI support.
          EFI support is only available for GRUB v2.
          This option is ignored for GRUB v1.
        '';
      };

      enableCryptodisk = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Enable support for encrypted partitions. GRUB should automatically
          unlock the correct encrypted partition and look for filesystems.
        '';
      };

      trustedBoot = {

        enable = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Enable trusted boot. GRUB will measure all critical components during
            the boot process to offer TCG (TPM) support.
          '';
        };

        systemHasTPM = mkOption {
          default = "";
          example = "YES_TPM_is_activated";
          type = types.string;
          description = ''
            Assertion that the target system has an activated TPM. It is a safety
            check before allowing the activation of 'trustedBoot.enable'. TrustedBoot
            WILL FAIL TO BOOT YOUR SYSTEM if no TPM is available.
          '';
        };

        isHPLaptop = mkOption {
          default = false;
          type = types.bool;
          description = ''
            Use a special version of TrustedGRUB that is needed by some HP laptops
            and works only for the HP laptops.
          '';
        };

      };

    };

  };


  ###### implementation

  config = mkMerge [

    {
      boot.loader.grub.fontTTF = mkDefault "${pkgs.dejavu-fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
    }

    (mkIf cfg.enable {

      boot.loader.grub.devices = optional (cfg.device != "") cfg.device;

      boot.loader.grub.mirroredBoots = optionals (cfg.devices != [ ]) [
        { path = "/boot"; inherit (cfg) devices; inherit (efi) efiSysMountPoint; }
      ];

      system.build.installBootLoader = pkgs.writeScript "install-grub.sh" (''
        #!${pkgs.stdenv.shell}
        set -e
        export PERL5LIB=${makeSearchPath "${pkgs.perlPackages.perl.libPrefix}" (with pkgs.perlPackages; [ FileSlurp XMLLibXML XMLSAX XMLSAXBase ListCompare ])}
        ${optionalString cfg.enableCryptodisk "export GRUB_ENABLE_CRYPTODISK=y"}
      '' + flip concatMapStrings cfg.mirroredBoots (args: ''
        ${pkgs.perlPackages.perl}/bin/perl ${./install-grub.pl} ${grubConfig args} $@
      ''));

      system.build.grub = grub;

      # Common attribute for boot loaders so only one of them can be
      # set at once.
      system.boot.loader.id = "grub";

      environment.systemPackages = optional (grub != null) grub;

      boot.loader.grub.extraPrepareConfig =
        concatStrings (mapAttrsToList (n: v: ''
          ${pkgs.coreutils}/bin/cp -pf "${v}" "/boot/${n}"
        '') config.boot.loader.grub.extraFiles);

      assertions = [
        {
          assertion = !cfg.zfsSupport || cfg.version == 2;
          message = "Only GRUB version 2 provides ZFS support";
        }
        {
          assertion = cfg.mirroredBoots != [ ];
          message = "You must set the option ???boot.loader.grub.devices??? or "
            + "'boot.loader.grub.mirroredBoots' to make the system bootable.";
        }
        {
          assertion = all (c: c < 2) (mapAttrsToList (_: c: c) bootDeviceCounters);
          message = "You cannot have duplicated devices in mirroredBoots";
        }
        {
          assertion = !cfg.trustedBoot.enable || cfg.version == 2;
          message = "Trusted GRUB is only available for GRUB 2";
        }
        {
          assertion = !cfg.efiSupport || !cfg.trustedBoot.enable;
          message = "Trusted GRUB does not have EFI support";
        }
        {
          assertion = !cfg.zfsSupport || !cfg.trustedBoot.enable;
          message = "Trusted GRUB does not have ZFS support";
        }
        {
          assertion = !cfg.trustedBoot.enable || cfg.trustedBoot.systemHasTPM == "YES_TPM_is_activated";
          message = "Trusted GRUB can break the system! Confirm that the system has an activated TPM by setting 'systemHasTPM'.";
        }
      ] ++ flip concatMap cfg.mirroredBoots (args: [
        {
          assertion = args.devices != [ ];
          message = "A boot path cannot have an empty devices string in ${args.path}";
        }
        {
          assertion = hasPrefix "/" args.path;
          message = "Boot paths must be absolute, not ${args.path}";
        }
        {
          assertion = if args.efiSysMountPoint == null then true else hasPrefix "/" args.efiSysMountPoint;
          message = "Efi paths must be absolute, not ${args.efiSysMountPoint}";
        }
      ] ++ flip map args.devices (device: {
        assertion = device == "nodev" || hasPrefix "/" device;
        message = "GRUB devices must be absolute paths, not ${dev} in ${args.path}";
      }));
    })

  ];


  imports =
    [ (mkRemovedOptionModule [ "boot" "loader" "grub" "bootDevice" ])
      (mkRenamedOptionModule [ "boot" "copyKernels" ] [ "boot" "loader" "grub" "copyKernels" ])
      (mkRenamedOptionModule [ "boot" "extraGrubEntries" ] [ "boot" "loader" "grub" "extraEntries" ])
      (mkRenamedOptionModule [ "boot" "extraGrubEntriesBeforeNixos" ] [ "boot" "loader" "grub" "extraEntriesBeforeNixOS" ])
      (mkRenamedOptionModule [ "boot" "grubDevice" ] [ "boot" "loader" "grub" "device" ])
      (mkRenamedOptionModule [ "boot" "bootMount" ] [ "boot" "loader" "grub" "bootDevice" ])
      (mkRenamedOptionModule [ "boot" "grubSplashImage" ] [ "boot" "loader" "grub" "splashImage" ])
    ];

}
