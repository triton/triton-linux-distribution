{ config, pkgs, ... }:

with pkgs.lib;

{
  options = {
    gnu = mkOption {
      default = false;
      description =
        '' When enable, GNU software is chosent by default whenever a there is
           a choice between GNU and non-GNU software (e.g., GNU lsh
           vs. OpenSSH).
        '';
    };
  };

  config = mkIf config.gnu {

    environment.systemPackages = with pkgs;
      # TODO: Adjust `requiredPackages' from `system-path.nix'.
      # TODO: Add Inetutils once it has the new `ifconfig'.
      [ parted fdisk
        nano zile
        texinfo # for the stand-alone Info reader
      ]
      ++ stdenv.lib.optional (!stdenv.isArm) grub2;


    # GNU GRUB, where available.
    boot.loader.grub.enable = !stdenv.isArm;
    boot.loader.grub.version = 2;

    # GNU lsh.
    services.openssh.enable = false;
    services.lshd.enable = true;
    services.xserver.startOpenSSHAgent = false;
    services.xserver.startGnuPGAgent = true;

    # TODO: GNU dico.
    # TODO: GNU Inetutils' inetd.
    # TODO: GNU Pies.
  };
}
