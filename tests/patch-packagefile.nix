{ lib, npmlock2nix, testLib }:
let
  inherit (testLib) noGithubHashes;
  i = npmlock2nix.internal;
in
(testLib.runTests {
  testTurnsGitHubRefsToWildcards = {
    expr =
      let
        leftpad = (npmlock2nix.internal.patchPackagefile noGithubHashes ./examples-projects/github-dependency/package.json).dependencies.leftpad;
      in
      leftpad == "*";
    expected = true;
  };
  testHandlesBranches = {
    expr =
      let
        leftpad = (npmlock2nix.internal.patchPackagefile noGithubHashes ./examples-projects/github-dependency-branch/package.json).dependencies.leftpad;
      in
      leftpad == "*";
    expected = true;
  };
  testHandlesDevDependencies = {
    expr =
      let
        leftpad = (npmlock2nix.internal.patchPackagefile noGithubHashes ./examples-projects/github-dev-dependency/package.json).devDependencies.leftpad;
      in
      leftpad == "*";
    expected = true;
  };
})
