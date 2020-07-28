{ lib
, writeTextFile
, writeShellScript
, nix
, smoke
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

  # Takes an attribute set of tests { description, shell, command, expected, (optional) status, (optional) temporary-directory = true }
  # an creates a bats script that executes them.
  makeIntegrationTests = tests:
    let
      mkTestScript = name: test:
        let
          shellDrv = (test.shell.overrideAttrs (_: { phases = [ "noopPhase" ]; noopPhase = "touch $out"; })).drvPath;
          temporaryDirectory = test.temporary-directory or true;
        in
        writeShellScript name ''
          export PATH="${nix}/bin:${coreutils}/bin"
          set -e
          ${lib.optionalString temporaryDirectory ''
            WORKING_DIR=$(mktemp -d)
            function cleanup {
              rm -rf "$WORKING_DIR"
            }
            trap cleanup EXIT
            cd $WORKING_DIR
          ''}
          nix-shell --pure ${shellDrv} --run "${writeShellScript "${name}-command" test.command}"
        '';
      testScripts = lib.mapAttrs (name: test: test // { script = mkTestScript name test; inherit name; }) tests;

      smokeConfig.tests = map
        (test: {
          inherit (test) name;
          command = test.script;
          stdout = test.expected;
          exit-status = test.status or 0;
        })
        (lib.attrValues testScripts);

      testScriptDir = writeTextFile {
        name = "smoke.yml";
        destination = "/smoke.yaml";
        text = builtins.toJSON smokeConfig;
      };
    in
    writeShellScript "tests" ''
      exec ${smoke}/bin/smoke ${testScriptDir}
    '';

}
