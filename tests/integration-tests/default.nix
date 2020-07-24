{ npmlock2nix, testLib, callPackage }:
testLib.makeIntegrationTests {

  shell = {
    description = "Require this projects shell expression to work";
    shell = import ../../shell.nix;
    command = ''
      type -a test-runner > /dev/null
      type -a node > /dev/null
      type -a smoke > /dev/null
      type -a niv > /dev/null
      type -a nixpkgs-fmt > /dev/null
    '';
    expected = "";
  };

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
}
