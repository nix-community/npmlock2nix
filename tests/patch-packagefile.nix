{ lib, npmlock2nix, testLib }:
let
  i = npmlock2nix.internal;
in
(testLib.runTests {
  testTurnsGitHubRefsToWildcards = {
    expr = (with npmlock2nix.internal; patchPackagefile { } (readPackageLikeFile ./examples-projects/github-dependency/package.json)).dependencies.leftpad;
    expected = "*";
  };
  testHandlesBranches = {
    expr = (with npmlock2nix.internal; patchPackagefile { } (readPackageLikeFile ./examples-projects/github-dependency-branch/package.json)).dependencies.leftpad;
    expected = "*";
  };
  testHandlesDevDependencies = {
    expr = (with npmlock2nix.internal; patchPackagefile { } (readPackageLikeFile ./examples-projects/github-dev-dependency/package.json)).devDependencies.leftpad;
    expected = "*";
  };
})
