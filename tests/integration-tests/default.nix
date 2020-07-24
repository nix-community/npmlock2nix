{ npmlock2nix, testLib }:
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
}
