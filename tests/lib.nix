{ lib }: {
  runTests = tests:
    let
      failures = lib.debug.runTests tests;
      msg = "Tests failed:\n" +
        lib.concatMapStringsSep "\n"
          (v: ''
            FAIL: ${v.name}
              expected: ${builtins.toJSON v.expected}
                   got: ${builtins.toJSON v.result}
          '')
          failures;
    in
    if builtins.length failures == 0 then [ ] else
    builtins.throw msg;
}
