{ npmlock2nix, testLib, symlinkJoin, runCommand, nodejs }:
testLib.runTests {
  # test that the shell expression uses the same (given) nodejs package for
  # both the shell and node_modules
  testUsesGivenNodeJSPackage =
    let
      custom_nodejs = symlinkJoin {
        name = "custom-nodejs";
        paths = [ nodejs ];
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
}
