{ npmlock2nix, testLib, runCommand, nodejs, python3 }:
testLib.runTests {
  testNodeModulesForEmptyDependencies = {
    expr =
      let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/no-dependencies;
        };
      in
      {
        inherit (drv) version name;
      };
    expected = {
      name = "no-dependencies-1.0.0";
      version = "1.0.0";
    };
  };


  testNodeModulesForEmptyDependenciesHasNodeModulesFolder = {
    expr =
      let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/no-dependencies;
        };
      in
      builtins.pathExists (drv + "/node_modules");
    expected = false;
  };

  testNodeModulesForSimpleProjectHasLeftPad = {
    expr =
      let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/single-dependency;
        };
      in
      builtins.pathExists (drv + "/node_modules/leftpad");
    expected = true;
  };
  testNodeModulesForSimpleProjectCanUseLeftPad = {
    expr =
      let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/single-dependency;
        };
      in
      builtins.pathExists (runCommand "test-leftpad"
        {
          buildInputs = [ nodejs ];
        } ''
        ln -s ${drv}/node_modules node_modules
        node -e "require('leftpad')"
        touch $out
      ''
      );
    expected = true;
  };

  testNodeModulesAcceptsCustomNodejs = {
    expr = (npmlock2nix.node_modules {
      src = ./examples-projects/no-dependencies;
      nodejs = "our-custom-nodejs-package";
    }).nodejs;
    expected = "our-custom-nodejs-package";
  };

  testNodeModulesPropagatesNodejs =
    let
      drv = npmlock2nix.node_modules {
        src = ./examples-projects/no-dependencies;
        nodejs = nodejs;
      };
    in
    {
      expr = drv.propagatedBuildInputs;
      expected = [ nodejs ];
    };

  testHonorsPrePostBuildHook =
    let
      drv = npmlock2nix.node_modules {
        src = ./examples-projects/single-dependency;
        preBuild = ''
          echo -n "preBuild" > preBuild-test
        '';
        postBuild = ''
          echo -n "postBuild" > postBuild-test
          mv *Build-test node_modules
        '';
      };
    in
    {
      expr = builtins.readFile (runCommand "concat"
        { } ''
        cat ${drv + "/node_modules/preBuild-test"} ${drv + "/node_modules/postBuild-test"} > $out
      ''
      );
      expected = "preBuildpostBuild";
    };

  testBuildsNativeExtensions =
    let
      drv = npmlock2nix.node_modules {
        src = ./examples-projects/native-extensions;
        buildInputs = [ python3 ];
      };
    in
    {
      expr = builtins.pathExists drv.outPath;
      expected = true;
    };

}
