{ nixos
, nixpkgs
, services ? "/etc/nixos/services"
, system ? builtins.currentSystem
, networkExpr
}:

let nodes = import networkExpr;
in
with import "${nixos}/lib/testing.nix" { inherit nixpkgs services system; };

(complete { inherit nodes; testScript = ""; }).driver
