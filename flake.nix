{
  description = "Utilizing npm lockfiles to create Nix expressions for NPM based projects. This projects aims to provide the following high-level build outputs:";

  outputs = { self }: {
    # self: super: must be named final: prev: for `nix flake check` to be happy
    overlay = final: prev: {
      npmlock2nix = prev.callPackage ./default.nix { pkgs = prev; };
    };
  };
}
