{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.hardware.opengl;

  kernelPackages = config.boot.kernelPackages;

  videoDrivers = config.services.xserver.videoDrivers;

  makePackage = p: pkgs.buildEnv {
    name = "mesa-drivers+txc-${p.mesa_drivers.version}";
    paths =
      [ p.mesa_drivers
        p.mesa # mainly for libGL
      ];
    passthru = p.mesa_drivers.passthru // p.mesa_noglu.passthru;
  };

  package = pkgs.buildEnv {
    name = "opengl-drivers-${cfg.package.system}";
    paths = [ cfg.package ] ++ cfg.extraPackages;
    inherit (cfg.package) passthru;
  };

  package32 = pkgs.buildEnv {
    name = "opengl-drivers-${cfg.package32.system}";
    paths = [ cfg.package32 ] ++ cfg.extraPackages32;
    inherit (cfg.package32) passthru;
  };

in

{
  options = {
    hardware.opengl.enable = mkOption {
      description = "Whether this configuration requires OpenGL.";
      type = types.bool;
      default = false;
      internal = true;
    };

    hardware.opengl.driSupport = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable accelerated OpenGL rendering through the
        Direct Rendering Interface (DRI).
      '';
    };

    hardware.opengl.driSupport32Bit = mkOption {
      type = types.bool;
      default = false;
      description = ''
        On 64-bit systems, whether to support Direct Rendering for
        32-bit applications (such as Wine).  This is currently only
        supported for the <literal>nvidia</literal> and 
        <literal>ati_unfree</literal> drivers, as well as
        <literal>Mesa</literal>.
      '';
    };

    hardware.opengl.package = mkOption {
      type = types.package;
      internal = true;
      description = ''
        The package that provides the OpenGL implementation.
      '';
    };

    hardware.opengl.package32 = mkOption {
      type = types.package;
      internal = true;
      description = ''
        The package that provides the 32-bit OpenGL implementation on
        64-bit systems. Used when <option>driSupport32Bit</option> is
        set.
      '';
    };

    hardware.opengl.extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExample "with pkgs; [ vaapiIntel libvdpau-va-gl vaapiVdpau ]";
      description = ''
        Additional packages to add to OpenGL drivers. This can be used
        to add additional VA-API/VDPAU drivers.
      '';
    };

    hardware.opengl.extraPackages32 = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExample "with pkgs; [ vaapiIntel libvdpau-va-gl vaapiVdpau ]";
      description = ''
        Additional packages to add to 32-bit OpenGL drivers on
        64-bit systems. Used when <option>driSupport32Bit</option> is
        set. This can be used to add additional VA-API/VDPAU drivers.
      '';
    };

  };

  config = mkIf cfg.enable {

    assertions = lib.singleton {
      assertion = cfg.driSupport32Bit -> pkgs.stdenv.isx86_64;
      message = "Option driSupport32Bit only makes sense on a 64-bit system.";
    };

    system.activation.scripts.setup-opengl =
      ''
        find /run -maxdepth 1 -name opengl-driver\* -exec rm -rf {} \;
        ln -sfn ${package} ${package.driverSearchPath}
        ${optionalString cfg.driSupport32Bit ''
          ln -sfn ${package32} ${package.driverSearchPath}
        ''}
      '';

    environment.sessionVariables.LD_LIBRARY_PATH = [
      "${package.driverSearchPath}/lib"
    ] ++ optionals cfg.driSupport32Bit [
      "${package32.driverSearchPath}/lib"
    ];

    hardware.opengl.package = mkDefault (makePackage pkgs);
    hardware.opengl.package32 = mkDefault (makePackage pkgs_32);

    boot.extraModulePackages = optional (elem "virtualbox" videoDrivers) kernelPackages.virtualboxGuestAdditions;
  };
}
