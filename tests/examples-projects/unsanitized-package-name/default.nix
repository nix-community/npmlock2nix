{ pkgs ? import ../../../nix { } }:
pkgs.npmlock2nix.build {
  src = ./.;
  buildCommands = [ "echo BUILDING" ];
  installPhase = "mkdir $out";
}
