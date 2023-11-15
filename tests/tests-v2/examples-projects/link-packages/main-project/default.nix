{ pkgs ? import ../../../../../nix { } }:

let
  linked-project = pkgs.callPackage ../linked-project { };
in
pkgs.npmlock2nix.v2.build {
  src = pkgs.nix-gitignore.gitignoreSource [ ] ./.;
  node_modules_attrs = {
    postFixup = ''
      ln -sfn ${linked-project} $out/node_modules/linked-project
    '';
  };
  installPhase = ''
    cp -r . $out

    # Validate that linked project is referenced correctly
    test -f $out/node_modules/linked-project/linked.js && echo "Project is linked correctly"
  '';
}
