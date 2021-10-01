{
  description = "Simple and unit tested solution to nixify npm based packages";

  # Don't make local registrya modifications affect what nixpkgs is used
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
      };
      main = import ./default.nix { inherit pkgs; };
    in {
      inherit (main) shell build node_modules internal;
    }
  );
}
