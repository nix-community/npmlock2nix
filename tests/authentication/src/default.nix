let
  npmlock2nixSource = <npmlock2nix>;
  pkgs = import <nixpkgs> { };
  npmlock2nix = import npmlock2nixSource { inherit pkgs; };
  lib = pkgs.lib;
in
npmlock2nix.shell {
  src = ./.;
  shellHook = ''
    node -e 'require("@someScope/hello")'
    exit
  '';
}
