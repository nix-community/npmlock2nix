{ pkgs ? import ../../../nix {} }:
let
  node = pkgs.nodejs-10_x;
in
assert pkgs.nodejs == node -> throw "default nodejs version has been updated. Please update the test";
pkgs.npmlock2nix.shell {
  src = ./.;
  nodejs = node;
}
