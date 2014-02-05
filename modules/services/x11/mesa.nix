{ config, pkgs, pkgs_i686, ... }:
let
  inherit (pkgs.lib) mkOption types mkIf optional optionals elem optionalString optionalAttrs;

  cfg = config.services.mesa;

  kernelPackages = config.boot.kernelPackages;
in {
  options = {
    services.mesa.enable = mkOption {
      description = "Whether this configuration requires mesa.";
      type = types.bool;
      default = false;
      internal = true;
    };

    services.mesa.driSupport = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable accelerated OpenGL rendering through the
        Direct Rendering Interface (DRI).
      '';
    };

    services.mesa.driSupport32Bit = mkOption {
      type = types.bool;
      default = false;
      description = ''
        On 64-bit systems, whether to support Direct Rendering for
        32-bit applications (such as Wine).  This is currently only
        supported for the <literal>nvidia</literal> driver and for
        <literal>mesa</literal>.
      '';
    };

    services.mesa.s3tcSupport = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Make S3TC(S3 Texture Compression) via libtxc_dxtn available
        to OpenGL drivers. It is essential for many games to work
        with FOSS GPU drivers.

        Using this library may require a patent license depending on your location.
      '';
    };


    services.mesa.videoDrivers = mkOption {
      type = types.listOf types.str;
      # !!! We'd like "nv" here, but it segfaults the X server.
      default = [ "ati" "cirrus" "intel" "vesa" "vmware" ];
      example = [ "vesa" ];
      description = ''
        The names of the video drivers that the mesa should
        support.  Mesa will try all of the drivers listed
        here until it finds one that supports your video card.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = pkgs.lib.singleton {
      assertion = cfg.driSupport32Bit -> pkgs.stdenv.isx86_64;
      message = "Option driSupport32Bit only makes sens on a 64-bit system.";
    };

    system.activationScripts.setup-opengl.deps = [];
    system.activationScripts.setup-opengl.text = ''
      rm -f /run/opengl-driver{,-32}
      ${optionalString (pkgs.stdenv.isi686) "ln -sf opengl-driver /run/opengl-driver-32"}
    ''
      #TODO:  The OpenGL driver should depend on what's detected at runtime.
     +( if elem "nvidia" cfg.videoDrivers then
          ''
            ln -sf ${kernelPackages.nvidia_x11} /run/opengl-driver
            ${optionalString cfg.driSupport32Bit
              "ln -sf ${pkgs_i686.linuxPackages.nvidia_x11.override { libsOnly = true; kernel = null; } } /run/opengl-driver-32"}
          ''
        else if elem "nvidiaLegacy173" cfg.videoDrivers then
          "ln -sf ${kernelPackages.nvidia_x11_legacy173} /run/opengl-driver"
        else if elem "nvidiaLegacy304" cfg.videoDrivers then
          ''
            ln -sf ${kernelPackages.nvidia_x11_legacy304} /run/opengl-driver
            ${optionalString cfg.driSupport32Bit
              "ln -sf ${pkgs_i686.linuxPackages.nvidia_x11_legacy304.override { libsOnly = true; kernel = null; } } /run/opengl-driver-32"}
          ''
        else if elem "ati_unfree" cfg.videoDrivers then
          "ln -sf ${kernelPackages.ati_drivers_x11} /run/opengl-driver"
        else
          ''
            ${optionalString cfg.driSupport "ln -sf ${pkgs.mesa_drivers} /run/opengl-driver"}
            ${optionalString cfg.driSupport32Bit
              "ln -sf ${pkgs_i686.mesa_drivers} /run/opengl-driver-32"}
          ''
      );

    environment.variables.LD_LIBRARY_PATH =
      [ "/run/opengl-driver/lib" "/run/opengl-driver-32/lib" ]
      ++ optional cfg.s3tcSupport "${pkgs.libtxc_dxtn}/lib"
      ++ optional (cfg.s3tcSupport && cfg.driSupport32Bit) "${pkgs_i686.libtxc_dxtn}/lib";

    boot.extraModulePackages =
      optional (elem "nvidia" cfg.videoDrivers) kernelPackages.nvidia_x11 ++
      optional (elem "nvidiaLegacy173" cfg.videoDrivers) kernelPackages.nvidia_x11_legacy173 ++
      optional (elem "nvidiaLegacy304" cfg.videoDrivers) kernelPackages.nvidia_x11_legacy304 ++
      optional (elem "virtualbox" cfg.videoDrivers) kernelPackages.virtualboxGuestAdditions ++
      optional (elem "ati_unfree" cfg.videoDrivers) kernelPackages.ati_drivers_x11;

    boot.blacklistedKernelModules =
      optionals (elem "nvidia" cfg.videoDrivers) [ "nouveau" "nvidiafb" ];

    environment.etc =  (optionalAttrs (elem "ati_unfree" cfg.videoDrivers) {
        "ati".source = "${kernelPackages.ati_drivers_x11}/etc/ati";
      })
      // (optionalAttrs (elem "nvidia" cfg.videoDrivers) {
        "OpenCL/vendors/nvidia.icd".source = "${kernelPackages.nvidia_x11}/lib/vendors/nvidia.icd";
      });
  };
}
