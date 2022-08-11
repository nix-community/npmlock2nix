{ lib, npmlock2nix, testLib }:
let
  inherit (testLib) noSourceOptions;
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
        resolved = (i.makeGithubSource noSourceOptions "leftpad" testDependency).json.resolved;
      in
      lib.hasPrefix "file:///nix/store" resolved;
    expected = true;
  };

  testDropsFrom = {
    expr =
      let
        dep = i.makeGithubSource noSourceOptions "leftpad" testDependency;
      in
      dep ? from;
    expected = false;
  };
})
