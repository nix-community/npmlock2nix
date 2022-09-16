{ npmlock2nix, testLib, lib }:
let
  inherit (testLib) noSourceOptions;
  i = npmlock2nix.v2.internal;
in
testLib.runTests {

  testPatchDependencyHandlesGitHubRefsInRequires = {
    expr =
      let
        libxmljsUrl = (i.patchDependency noSourceOptions "test" {
          version = "github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
          from = "github:tmcw/leftpad#db1442a0556c2b133627ffebf455a78a1ced64b9";
          integrity = "sha512-8/UvHFG90J4O4QNRzb0jB5Ni1QuvuB7XFTLfDMQnCzAsFemF29VKnNGUESFFcSP/r5WWh/PMe0YRz90+3IqsUA==";
          requires = {
            libxmljs = "github:znerol/libxmljs#0517e063347ea2532c9fdf38dc47878c628bf0ae";
          };
        }
        ).result.requires.libxmljs;
      in
      lib.hasPrefix builtins.storeDir libxmljsUrl;
    expected = true;
  };

  testBundledDependenciesAreRetained = {
    expr = (i.patchDependency noSourceOptions "test" {
      bundled = true;
      integrity = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
      something = "bar";
      dependencies = { };
    }).result;
    expected = {
      bundled = true;
      integrity = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
      something = "bar";
      dependencies = { };
    };
  };

  testPatchLockfileWithoutDependencies = {
    expr = (i.patchLockfile noSourceOptions (i.readPackageLikeFile ./examples-projects/no-dependencies/package-lock.json)).result.dependencies;
    expected = { };
  };

  testPatchDependencyDoesntDropAttributes = {
    expr = (i.patchDependency noSourceOptions "test" {
      a = 1;
      foo = "something";
      resolved = "https://examples.com/something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies = { };
    }).result;
    expected = {
      a = 1;
      foo = "something";
      resolved = "file:///nix/store/k2rgngn9cmhz4g3kzxmvhx5r40qvnwcf-something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies = { };
    };
  };

  testPatchDependencyPatchesDependenciesRecursively = {
    expr = (i.patchDependency noSourceOptions "test" {
      a = 1;
      foo = "something";
      resolved = "https://examples.com/something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies.a = {
        resolved = "https://examples.com/somethingelse.tgz";
        integrity = "sha1-00000000000000000000000+00U=";
      };
    }).result;

    expected = {
      a = 1;
      foo = "something";
      resolved = "file:///nix/store/k2rgngn9cmhz4g3kzxmvhx5r40qvnwcf-something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies.a = {
        resolved = "file:///nix/store/1cf0n1xb5pad8ib3xyzbzzddfknfxvkc-somethingelse.tgz";
        integrity = "sha1-00000000000000000000000+00U=";
      };
    };
  };

  testPatchLockfileTurnsUrlsIntoStorePaths = {
    expr =
      let
        deps = (i.patchLockfile noSourceOptions (i.readPackageLikeFile ./examples-projects/single-dependency/package-lock.json)).result.dependencies;
      in
      lib.count (dep: lib.hasPrefix "file:///nix/store/" dep.resolved) (lib.attrValues deps);
    expected = 1;
  };

  testPatchLockfileTurnsGitHubUrlsIntoStorePaths = {
    expr =
      let
        leftpad = (i.patchLockfile noSourceOptions (i.readPackageLikeFile ./examples-projects/github-dependency/package-lock.json)).result.dependencies.leftpad;
      in
      lib.hasPrefix ("file://" + builtins.storeDir) leftpad.resolved;
    expected = true;
  };

  testConvertPatchedLockfileToJSON = {
    expr =
      let
        patchedLockfile = i.patchLockfile noSourceOptions (i.readPackageLikeFile ./examples-projects/nested-dependencies/package-lock.json);
      in
      (builtins.typeOf (builtins.toJSON patchedLockfile.result) == "string");
    expected = true;
  };

  testPatchedLockFile =
    let
      patchedLockfile = (i.patchedLockfile noSourceOptions (i.readPackageLikeFile ./examples-projects/nested-dependencies/package-lock.json));
    in
    {
      expr = testLib.hashFile "${patchedLockfile}";
      expected = "00da07928784d509365ef9681f894fbfc58a38db43847e3955d1777e2f4f5e57";
    };

}
