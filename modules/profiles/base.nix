# This module defines the software packages included in the "minimal"
# installation CD.  It might be useful elsewhere.

{ config, lib, pkgs, ... }:

{
  # Include some utilities that are useful for installing or repairing
  # the system.
  environment.systemPackages = [
    pkgs.ms-sys # for writing Microsoft boot sectors / MBRs
    pkgs.efibootmgr
    pkgs.efivar
    pkgs.gptfdisk
    pkgs.ddrescue
    pkgs.cryptsetup # needed for dm-crypt volumes

    # Hardware-related tools.
    pkgs.sdparm
    pkgs.hdparm
    pkgs.mdadm
    pkgs.smartmontools # for diagnosing hard disks
    pkgs.pciutils
    pkgs.usbutils

    # Tools to create / manipulate filesystems.
    pkgs.ntfs-3g # for resizing NTFS partitions
    pkgs.dosfstools
    pkgs.xfsprogs
    pkgs.f2fs-tools

    # Tools for building
    pkgs.stdenv
    pkgs.git
    pkgs.mg
    pkgs.nano
    pkgs.vim

    # Misc tools
    config.programs.ssh.package
    pkgs.dnsutils
    pkgs.htop
    pkgs.iftop
    pkgs.iotop
    pkgs.mtr
    pkgs.nmap
    pkgs.openssl
    pkgs.gnupg
    pkgs.tmux
    pkgs.screen
  ];

  # Include support for various filesystems.
  boot.supportedFilesystems = [ "btrfs" "vfat" "f2fs" "xfs" "zfs" "ntfs" ];

  # Configure host id for ZFS to work
  networking.hostId = lib.mkDefault "8425e349";
}
