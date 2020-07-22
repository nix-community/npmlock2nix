{ pkgs ? import ../../../nix, version ? "12_x"}:
pkgs.npmlock2nix.shell {
  src = ./.;
  nodejs = pkgs."nodejs-${version}";
}
