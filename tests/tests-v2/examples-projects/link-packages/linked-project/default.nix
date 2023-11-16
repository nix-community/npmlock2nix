{ pkgs ? import ../../../../../nix { } }:

pkgs.npmlock2nix.v2.build {
  src = pkgs.nix-gitignore.gitignoreSource [ "*.nix" ] ./.;
  installPhase = "cp -r . $out";
}
