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

  # Takes an attribute set of tests { description, shell, command, expected, (optional) status }
  # an creates a bats script that executes them.
  makeIntegrationTests = tests:
    let
      mkTestScript = name: shell: command:
        let
          shellDrv = (shell.overrideAttrs (_: { phases = [ "noopPhase" ]; noopPhase = "touch $out"; })).drvPath; in
        writeShellScript name ''
          export PATH="${nix}/bin:${coreutils}/bin"
          exec nix-shell --pure ${shellDrv} --run "${writeShellScript "${name}-command" command}"
        '';
      testScripts = lib.mapAttrs (name: test: test // { script = mkTestScript name test.shell test.command; inherit name; }) tests;

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
