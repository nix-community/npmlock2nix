{ lib, npmlock2nix, testLib }:
let
  inherit (testLib) noGithubHashes;
  i = npmlock2nix.internal;

  testDependency = {
    version = "github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
    from = "github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
  };
in
(testLib.runTests {
  testSimpleCase = {
    expr =
      let
        version = (i.makeGithubSource noGithubHashes "leftpad" testDependency).version;
      in
      lib.hasPrefix "file:///nix/store" version;
    expected = true;
  };

  testDropsFrom = {
    expr =
      let
        dep = i.makeGithubSource noGithubHashes "leftpad" testDependency;
      in
      dep ? from;
    expected = false;
  };
})
