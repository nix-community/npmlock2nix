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
  webpack-cli-project = npmlock2nix.build {
    src = ./examples-projects/webpack-cli-project;
    npmCommands = [ "webpack --mode=production" ];
    installPhase = ''
      cp -r dist $out
    '';
  };
}
