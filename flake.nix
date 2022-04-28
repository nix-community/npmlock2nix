{
  description = "A nix flake to nixify npm based packages.";
  outputs = { self }: {
    overlay =
      (self: super: {
        npmlock2nix = super.callPackage ./default.nix { };
      });
  };
}
