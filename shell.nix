let
  pkgs = import ./nix {};

  test-runner = pkgs.writeScriptBin "test-runner" ''
    find . -type f | ${pkgs.entr}/bin/entr -c nix-build -A tests --show-trace
  '';

in pkgs.mkShell {
  buildInputs = [ test-runner pkgs.nodejs pkgs.smoke ];
}
