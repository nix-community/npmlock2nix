{ newScope }:
let
  callPackage = newScope testPkgs;
  testPkgs = {
    testLib = callPackage ./lib.nix { };
  };
in
{
  make-github-source = callPackage ./make-github-source.nix { };
  parse-github-ref = callPackage ./parse-github-ref.nix { };
  read-lockfile = callPackage ./read-lockfile { };
  make-source-urls = callPackage ./make-source-urls.nix { };
  patch-lockfile = callPackage ./patch-lockfile.nix { };
  patch-packagefile = callPackage ./patch-packagefile.nix { };
  node-modules = callPackage ./node-modules.nix { };
  shell = callPackage ./shell.nix { };
  integration-tests = callPackage ./integration-tests { };
  build-tests = callPackage ./build-tests.nix { };
  source-hash-func = callPackage ./source-hash-func.nix { };
}
