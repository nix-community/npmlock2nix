{ pkgs ? import ./nix { } }:
let
  internal = pkgs.callPackage ./internal.nix { };
in
{
  inherit (internal) shell build node_modules;

  tests = pkgs.callPackage ./tests { };


  # *** WARNING ****
  # using any of the functions exposed by `internal` is not supported. That
  # being said, hiding them would only lead to copy&paste and it is also useful
  # for testing internal building blocks.
  internal = builtins.trace "npmlock2nix: You are using the unsupported internal API." (
    internal
  );
}
