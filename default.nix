{ pkgs ? import ./nix { }, lib ? pkgs.lib }:
let
  v1_internal = pkgs.callPackage ./internal-v1.nix { };
  v2_internal = pkgs.callPackage ./internal-v2.nix { };
  separatePublicAndInternalAPI = api: {
    inherit (api) shell build node_modules;

    # *** WARNING ****
    # using any of the functions exposed by `internal` is not supported. That
    # being said, hiding them would only lead to copy&paste and it is also useful
    # for testing internal building blocks.
    internal = lib.warn "[npmlock2nix] You are using the unsupported internal API." (
      api
    );
  };
  v1 = separatePublicAndInternalAPI v1_internal;
  v2 = separatePublicAndInternalAPI v2_internal;
  withWarning = f: lib.warn "[npmlock2nix] Using deprecated legacy accessors. Will be removed afer 2022-12-31. Please specify the v1 or v2 npm lockfile format you want to use through the top-level v1 and v2 attrsets." f;
in
{
  inherit v1 v2;
  tests-v1 = pkgs.callPackage ./tests-v1 { };
} // (lib.mapAttrs (_: withWarning) v1)
