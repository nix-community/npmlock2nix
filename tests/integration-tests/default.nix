{ npmlock2nix, testLib, callPackage, libwebp }:
testLib.makeIntegrationTests {
  leftpad = {
    description = "Require a node dependency inside the shell environment";
    shell = npmlock2nix.shell { src = ../examples-projects/single-dependency; };
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
    shell = npmlock2nix.shell { src = ../examples-projects/bin-project; };
    command = ''
      mkdirp --version
    '';
    expected = "1.0.4\n";
  };

  symlinkNodeModules =
    let
      shell = npmlock2nix.shell {
        src = ../examples-projects/bin-project;
        node_modules_mode = "symlink";
      };
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
      shell = npmlock2nix.shell {
        src = ../examples-projects/bin-project;
        node_modules_mode = "symlink";
      };
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

  copyNodeModulesDoesNotOverrideExistingNodeModules =
    let
      shell = npmlock2nix.shell {
        src = ../examples-projects/bin-project;
        node_modules_mode = "copy";
      };
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

  symlinkNodeModulesCreatesALink =
    let
      shell = npmlock2nix.shell {
        src = ../examples-projects/bin-project;
        node_modules_mode = "symlink";
      };
    in
    {
      description = ''
        Ensure the shellHook does create a symlink.
      '';
      inherit shell;
      command = ''
        test -L node_modules || exit 1
      '';
      expected = "";
    };

  copyNodeModulesCreatesANewDirectory =
    let
      shell = npmlock2nix.shell {
        src = ../examples-projects/bin-project;
        node_modules_mode = "copy";
      };
    in
    {
      description = ''
        Ensure the shellHook does create a directory.
      '';
      inherit shell;
      command = ''
        test -d node_modules || exit 1
      '';
      expected = "";
    };


  webpackCli = {
    description = ''
      We should be able to invoke the webpack(-cli) to build a very simple bootstrap based project
    '';
    shell = npmlock2nix.shell {
      src = ../examples-projects/webpack-cli-project;
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

  bin-wrapped-dep = {
    description = ''
      Some packages try to download files into their source folder when they
      are missing.
      One of these packages is `cwebp-bin` that is based on the `bin-wrapper`
      package. The common pattern here is that they check for their binary (in
      this case `cwebp`) in the `vendor` directory of the package in the
      node_modules folder.

      In this test we are verifying that those node projects can be built and
      the binaries are availble during runtime (through node).

      We expect the path returned by nodejs to be a symlink to the actual store path.
    '';

    shell = callPackage ../examples-projects/bin-wrapped-dep/shell.nix { };
    command = ''
      readlink -f $(node -e 'console.log(require("cwebp-bin"))')
    '';

    expected = ''
      ${libwebp}/bin/cwebp
    '';
  };
  warnAboutGithubDependencies = {
    description = ''
      Ensure that we warn about github: dependencies and abort the eval if they are encoutered.
    '';
    evalFailure = true;
    shell = npmlock2nix.shell {
      src = ../examples-projects/github-dependency;
    };
    command = ''
      exit 123
    '';
    status = 1;
    expected = "";
    expected-stderr = ''
      error: [npmlock2nix] The given package-lock.json contains sources that refer to GitHub. The source spec is often not precise enough to be translated into a (reliable) Nix git fetch invocation.
      (use '--show-trace' to show detailed location information)
    '';
  };
}
