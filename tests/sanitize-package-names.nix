{ testLib, npmlock2nix, lib }:
let
  i = npmlock2nix.internal;
in
testLib.runTests (
  ({
    # Using only a-zA-Z0-9 and a few selected special chars is allowed.
    testIsValidDrvNameCharHappyPath = {
      expr = i.isValidDrvNameChar "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890_-.=";
      expected = true;
    };

  }) // (
    # build a set of tests, one for each of the characters that should be rejected
    # The test results will help with debugging and look like this in case they fail:
    #
    #  FAIL: testIsValidDrvNameCharRejects: "-"
    #  expected: false
    #       got: true
    let
      cases = [ "!" "%" "^" "/" "\\" "#" "*" "(" ")" "@" "\"" "'" "?" ];
      mkCase = case: { expr = i.isValidDrvNameChar case; expected = false; };
    in
    lib.mapAttrs' (key: value: lib.nameValuePair "testIsValidDrvNameCharRejects: \"${key}\"" value) (
      lib.genAttrs cases mkCase
    )
  ) // (
    # Test that paths are being sanitized by our makeValidDrvName function.
    # We map the test cases from a (input, output)-style attribute set into the test structure such that we will receive human-friendly error messages when the tests fail.
    let
      cases = {
        "asdf-123.-_" = "asdf-123.-_";
        "ABCDEF$!%^/\\#*()@-'?" = "ABCDEF___________-__";
      };
      mkCase = (input: expected: { inherit expected; expr = i.makeValidDrvName input; });
    in
    lib.mapAttrs' (input: expected: lib.nameValuePair "testMakeValidDrvName: \"${input}\"" (mkCase input expected)) cases
  )
)
