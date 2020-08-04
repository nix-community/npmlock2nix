{ lib, symlinkJoin, npmlock2nix, runCommand }:
let
  symlinkAttrs = attrs: runCommand "symlink-attrs"
    { }
    (
      let
        drvs = lib.attrValues (lib.mapAttrs (name: drv: { inherit name drv; }) attrs);
      in
      ''
          mkdir $out
        ${lib.concatMapStringsSep "\n" (o: "ln -s ${o.drv} $out/${o.name}") drvs}
      ''
    );
in
symlinkAttrs {
  webpack-cli-project-default-build-command = npmlock2nix.build {
    src = ./examples-projects/webpack-cli-project;
    installPhase = ''
      cp -r dist $out
    '';
  };

  webpack-cli-project-custom-build-command = npmlock2nix.build {
    src = ./examples-projects/webpack-cli-project;
    buildCommands = [ "webpack --mode=production" ];
    installPhase = ''
      cp -r dist $out
    '';
  };

}
