{ npmlock2nix, testLib, lib }:
testLib.runTests {

  testBundledDependenciesAreRetained = {
    expr = npmlock2nix.internal.patchDependency "test" {
      bundled = true;
      integrity = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
      something = "bar";
      dependencies = { };
    };
    expected = {
      bundled = true;
      integrity = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
      something = "bar";
      dependencies = { };
    };
  };

  testPatchLockfileWithoutDependencies = {
    expr = (npmlock2nix.internal.patchLockfile ./examples-projects/no-dependencies/package-lock.json).dependencies;
    expected = { };
  };

  testPatchDependencyDoesntDropAttributes = {
    expr = npmlock2nix.internal.patchDependency "test" {
      a = 1;
      foo = "something";
      resolved = "https://examples.com/something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies = { };
    };
    expected = {
      a = 1;
      foo = "something";
      resolved = "file:///nix/store/n0zkv46bvcasr2lak6lj09yjgnhia0hr-test";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies = { };
    };
  };

  testPatchDependencyPatchesDependenciesRecursively = {
    expr = npmlock2nix.internal.patchDependency "test" {
      a = 1;
      foo = "something";
      resolved = "https://examples.com/something.tgz";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies.a = {
        resolved = "https://examples.com/somethingelse.tgz";
        integrity = "sha1-00000000000000000000000+00U=";
      };
    };

    expected = {
      a = 1;
      foo = "something";
      resolved = "file:///nix/store/n0zkv46bvcasr2lak6lj09yjgnhia0hr-test";
      integrity = "sha1-00000000000000000000000+0RU=";
      dependencies.a = {
        resolved = "file:///nix/store/cvx014pf1c8r8lfx3xnqrnn8nl5qnjd0-a";
        integrity = "sha1-00000000000000000000000+00U=";
      };
    };
  };

  testPatchLockfileTurnsUrlsIntoStorePaths = {
    expr =
      let
        deps = (npmlock2nix.internal.patchLockfile ./examples-projects/single-dependency/package-lock.json).dependencies;
      in
      lib.count (dep: lib.hasPrefix "file:///nix/store/" dep.resolved) (lib.attrValues deps);
    expected = 1;
  };

  testConvertPatchedLockfileToJSON = {
    expr = builtins.typeOf (builtins.toJSON (npmlock2nix.internal.patchLockfile ./examples-projects/nested-dependencies/package-lock.json)) == "string";
    expected = true;
  };

  testPatchedLockFile = {
    expr = testLib.hashFile (npmlock2nix.internal.patchedLockfile ./examples-projects/nested-dependencies/package-lock.json);
    expected = "5956967f875fd8f4de2202b42314b276a3e88c1daf882e77ab25e865b40721f9";
  };

}
