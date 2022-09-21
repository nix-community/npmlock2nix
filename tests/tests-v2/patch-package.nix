{ lib, npmlock2nix, testLib }:
let
  inherit (testLib) noSourceOptions;
  i = npmlock2nix.v2.internal;

  specRef = {
    resolved = "github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
    version = "0.0";
  };
  specGitRef = {
    resolved = "leftpad@github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
    version = "0.0";
  };
  specGitFull = {
    resolved = "git+ssh://git@github.com/tmcw/leftpad.git#db1442a0556c2b133627ffebf455a78a1ced64b9";
    version = "0.0";
  };
in
(testLib.runTests {
  testGhSourceRef = {
    expr =
      let
        version = (i.patchPackage noSourceOptions "leftpad" specRef).resolved;
      in
      lib.hasPrefix "file:///nix/store" version;
    expected = true;
  };
  testGhSourceGitRef = {
    expr =
      let
        version = (i.patchPackage noSourceOptions "leftpad" specGitRef).resolved;
      in
      lib.hasPrefix "file:///nix/store" version;
    expected = true;
  };
  testGhSourceGitRefFull = {
    expr =
      let
        version = (i.patchPackage noSourceOptions "leftpad" specGitFull).resolved;
      in
      lib.hasPrefix "file:///nix/store" version;
    expected = true;
  };
  testPatchDepRegistry = {
    expr =
      let
        res = (i.patchPackage noSourceOptions "node_modules/yallist" {
          version = "4.0.0";
          resolved = "https://registry.npmjs.org/yallist/-/yallist-4.0.0.tgz";
          integrity = "sha512-3wdGidZyq5PB084XLES5TpOSRA3wjXAlIWMhum2kRcv/41Sn2emQ0dycQW4uZXLejwKvg6EsvbdlVL+FYEct7A==";
        });
      in
      res.version == "4.0.0" && lib.hasPrefix "file:///nix/store" res.resolved && res.integrity == "sha512-3wdGidZyq5PB084XLES5TpOSRA3wjXAlIWMhum2kRcv/41Sn2emQ0dycQW4uZXLejwKvg6EsvbdlVL+FYEct7A==";
    expected = true;
  };
  testPatchDepGithub = {
    expr =
      let
        res = (i.patchPackage noSourceOptions "node_modules/leftpad" {
          version = "0.0.1";
          resolved = "git+ssh://git@github.com/tmcw/leftpad.git#db1442a0556c2b133627ffebf455a78a1ced64b9";
          integrity = "sha512-8NCRwDs07XJJnyO7d6fVbrKjpW1nkbH0dFH5v2/U7md4+4y2hL8+S9OpRqY54W22Dq45yFKuVUYmLlrjGeFLOw==";
          license = "BSD-3-Clause";
        });
      in
      lib.hasPrefix "file:///nix/store" res.resolved && res.integrity == null;
    expected = true;
  };


})
