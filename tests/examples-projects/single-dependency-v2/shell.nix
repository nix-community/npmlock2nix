{ pkgs ? import ../../../nix { } }:
pkgs.npmlock2nix.shell {
  src = ./.;
  nodejs = pkgs.nodejs-16_x;
}
