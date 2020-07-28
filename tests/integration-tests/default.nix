{ npmlock2nix, testLib }:
testLib.makeIntegrationTests {
  leftpad = {
    description = "Require a node dependency inside the shell environment";
    shell = npmlock2nix.shell { src = ../examples-projects/single-dependency; symlink_node_modules = false; };
    command = ''
      node -e 'console.log(require("leftpad")(123, 7));'
    '';
    expected = "0000123\n";
  };
  nodejsVersion = {
    description = "Specify nodejs version to use";
    shell = import ../examples-projects/nodejs-version-shell/shell.nix { };
    command = ''
      node -e 'console.log(process.versions.node.split(".")[0]);'
    '';
    expected = "10\n";
  };
  pathContainsNodeApplications = {
    description = "Applications from the node_modules/.bin folder should be available on $PATH in the shell expression";
    shell = npmlock2nix.shell { src = ../examples-projects/bin-project; symlink_node_modules = false; };
    command = ''
      mkdirp --version
    '';
    expected = "1.0.4\n";
  };

  symlinkNodeModules =
    let
      shell = npmlock2nix.shell { src = ../examples-projects/bin-project; symlink_node_modules = true; };
    in
    {
      description = ''
        The shell builder supports linking the nix build node_modules folder into
        the current working directory via the `shellHook`. Verify taht we are
        indeed doing that.
      '';
      inherit shell;
      command = ''
        readlink -f node_modules
      '';
      expected = toString (shell.node_modules + "/node_modules\n");
    };

  symlinkNodeModulesDoesNotOverrideExistingNodeModules =
    let
      shell = npmlock2nix.shell { src = ../examples-projects/bin-project; symlink_node_modules = true; };
    in
    {
      description = ''
        Ensure the shellHook doesn't override node_modules directory.
      '';
      inherit shell;
      setup-command = ''
        mkdir node_modules
      '';
      command = ''
        readlink -f node_modules
      '';
      status = 1;
      expected = "";
      expected-stderr = ''
        [npmlock2nix] There is already a `node_modules` directory. Not replacing it.
      '';
    };

  webpackCli = {
    description = ''
      We should be able to invoke the webpack(-cli) to build a very simple bootstrap based project
    '';
    shell = npmlock2nix.shell {
      src = ../examples-projects/webpack-cli-project;
      symlink_node_modules = true;
    };
    setup-command = ''
      cp --no-preserve=mode -r ${testLib.withoutNodeModules ../examples-projects/webpack-cli-project} workspace
      cd workspace
    '';
    command = ''
      webpack-cli --version
      if ! webpack --mode production > .webpack.log 2>&1; then
        cat .webpack.log
        exit 1
      fi
      if ! test -e dist/main.js; then
        echo "dist/main.js missing"
        exit 1
      fi
      if ! test -e dist/index.html; then
        echo "dist/index.html missing"
        exit 1
      fi
    '';
    expected = ''
      3.3.12
    '';
  };
}
