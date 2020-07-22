{ npmlock2nix, testLib, runCommand, nodejs }:
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
      expr = let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/no-dependencies;
        };
      in  builtins.pathExists (drv + "/node_modules");
      expected = false;
  };

  testNodeModulesForSimpleProjectHasLeftPad = {
      expr = let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/single-dependency;
        };
      in  builtins.pathExists (drv + "/node_modules/leftpad");
      expected = true;
  };
  testNodeModulesForSimpleProjectCanUseLeftPad = {
      expr = let
        drv = npmlock2nix.node_modules {
          src = ./examples-projects/single-dependency;
        };
      in builtins.pathExists (runCommand "test-leftpad" {
        buildInputs = [ nodejs ];
      } ''
        ln -s ${drv}/node_modules node_modules
        node -e "require('leftpad')"
        touch $out
      '');
      expected = true;
  };

}
