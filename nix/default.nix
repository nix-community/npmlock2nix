{}:
let
  sources = import ./sources.nix;
in
import sources.nixpkgs {
  overlays = [
    (self: super: {
      npmlock2nix = self.callPackage ../default.nix { };
      inherit (self.callPackage (import sources.smoke) { }) smoke;
      nix-pre-commit-hooks = import (sources.nix-pre-commit-hooks);
    })
  ];
}
