# Provide an initial copy of the NixOS channel so that the user
# doesn't need to run "nix-channel --update" first.

{ config, pkgs, ... }:

with pkgs.lib;

let

  # We need a copy of the Nix expressions for Nixpkgs and NixOS on the
  # CD.  These are installed into the "nixos" channel of the root
  # user, as expected by nixos-rebuild/nixos-install.
  channelSources = pkgs.runCommand "nixos-${config.system.nixosVersion}"
    { expr = builtins.readFile ../../../lib/channel-expr.nix; }
    ''
      mkdir -p $out/nixos
      cp -prd ${cleanSource ../../..} $out/nixos/nixos
      cp -prd ${cleanSource <nixpkgs>} $out/nixos/nixpkgs
      chmod -R u+w $out/nixos/nixos
      echo -n ${config.system.nixosVersion} > $out/nixos/nixos/.version
      echo -n "" > $out/nixos/nixos/.version-suffix
      echo "$expr" > $out/nixos/default.nix
    '';

in

{
  # Provide the NixOS/Nixpkgs sources in /etc/nixos.  This is required
  # for nixos-install.
  boot.postBootCommands =
    ''
      echo "unpacking the NixOS/Nixpkgs sources..."
      mkdir -p /nix/var/nix/profiles/per-user/root
      ${config.environment.nix}/bin/nix-env -p /nix/var/nix/profiles/per-user/root/channels -i ${channelSources} --quiet
      mkdir -m 0700 -p /root/.nix-defexpr
      ln -s /nix/var/nix/profiles/per-user/root/channels /root/.nix-defexpr/channels
    '';
}
