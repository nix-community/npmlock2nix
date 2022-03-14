{ lib, npmlock2nix, testLib }:
let
  i = npmlock2nix.internal;
in
(testLib.runTests {
  testTurnsGitHubRefsToWildcards = {
    expr = (npmlock2nix.internal.patchPackagefile ./examples-projects/github-dependency/package.json).dependencies.leftpad;
    expected = "*";
  };
  testHandlesBranches = {
    expr = (npmlock2nix.internal.patchPackagefile ./examples-projects/github-dependency-branch/package.json).dependencies.leftpad;
    expected = "*";
  };
  testHandlesDevDependencies = {
    expr = (npmlock2nix.internal.patchPackagefile ./examples-projects/github-dev-dependency/package.json).devDependencies.leftpad;
    expected = "*";
  };
})
