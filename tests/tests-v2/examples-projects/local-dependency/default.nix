{ pkgs ? import ../../../../nix { } }:

pkgs.npmlock2nix.v2.node_modules {
  src = ./.;
  packageJson = ./package.json;
  packageLockJson = ./package-lock.json;
  localPackages = {
    leftpad = ../local-leftpad;
  };
}
