{ pkgs ? import ../../../nix { } }:
pkgs.npmlock2nix.shell {
  src = ./.;
}
