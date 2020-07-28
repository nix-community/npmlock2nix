let
  pkgs = import ./nix { };

  watch-tests = pkgs.writeScriptBin "watch-tests" ''
    find . -type f | ${pkgs.entr}/bin/entr -c ./test.sh
  '';

  pre-commit-hooks = pkgs.nix-pre-commit-hooks.run {
    src = ./.;
    hooks = {
      nixpkgs-fmt.enable = true;
    };
  };

in
pkgs.mkShell {
  buildInputs = [ watch-tests pkgs.nodejs pkgs.smoke pkgs.niv pkgs.nixpkgs-fmt ];
  inherit (pre-commit-hooks) shellHook;
}
