{ lib
, writeScript
, writeShellScript
, nix
, bats
, coreutils
}: {
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

  # Takes an attribute set of tests { description, shell, command, expected, (optional) status }
  # an creates a bats script that executes them.
  makeIntegrationTests = tests:
    let
      mkTestScript = name: shell: command:
        let
          shellDrv = builtins.unsafeDiscardStringContext shell.drvPath;
        in
        writeShellScript name ''
          export PATH="${nix}/bin:${coreutils}/bin"
          exec nix-shell --pure ${shellDrv} --run "${writeShellScript "${name}-command" command}"
        '';
      testScripts = lib.mapAttrs (name: test: test // { script = mkTestScript name test.shell test.command; inherit name; }) tests;

      text = lib.concatMapStringsSep "\n"
        (test: ''
          @test "${test.name} - ${test.description}" {
            run ${test.script}

            echo $output > /tmp/debug.log

            [[ "$status" -eq ${test.status or "0"} ]]
            [[ "$output" = "${test.expected}" ]]
          }
        '')
        (builtins.attrValues testScripts);

    in
    writeScript "tests.bats" ''
      #!${bats}/bin/bats
      ${text}
    '';

}
