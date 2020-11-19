{ npmlock2nix, testLib, symlinkJoin, runCommand, nodejs }:
testLib.runTests {
  # test that the shell expression uses the same (given) nodejs package for
  # both the shell and node_modules
  testUsesGivenNodeJSPackage =
    let
      custom_nodejs = symlinkJoin {
        name = "custom-nodejs";
        paths = [ nodejs ];
        version = "12.8.3";
        src = "/foo";
      };
      drv = npmlock2nix.shell {
        src = ./examples-projects/single-dependency;
        nodejs = custom_nodejs;
      };
    in
    {
      expr = {
        inherit (drv) buildInputs;
        node_modules_nodejs = drv.node_modules.nodejs;
      };
      expected = {
        buildInputs = [ custom_nodejs drv.node_modules ];
        node_modules_nodejs = custom_nodejs;
      };
    };

  # test that we are passing the pre- & postBuild attributes to node_modules
  testPassPreBuildAttributeToNodeModules =
    let
      drv = npmlock2nix.shell {
        src = ./examples-projects/single-dependency;
        node_modules_attrs.preBuild = "foobar in preBuild";
      };
    in
    {
      expr = drv.node_modules.preBuild;
      expected = "foobar in preBuild";
    };

  testPassPostBuildAttributeToNodeModules =
    let
      drv = npmlock2nix.shell {
        src = ./examples-projects/single-dependency;
        node_modules_attrs.postBuild = "foobar in postBuild";
      };
    in
    {
      expr = drv.node_modules.postBuild;
      expected = "foobar in postBuild";
    };

}
