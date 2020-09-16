{ newScope }:
let
  callPackage = newScope testPkgs;
  testPkgs = {
    testLib = callPackage ./lib.nix { };
  };
in
{
  read-lockfile = callPackage ./read-lockfile { };
  make-source-urls = callPackage ./make-source-urls.nix { };
  patch-lockfile = callPackage ./patch-lockfile.nix { };
  node-modules = callPackage ./node-modules.nix { };
  shell = callPackage ./shell.nix { };
  integration-tests = callPackage ./integration-tests { };
  build-tests = callPackage ./build-tests.nix { };
  yarn = callPackage ./test-yarn.nix { };
}
