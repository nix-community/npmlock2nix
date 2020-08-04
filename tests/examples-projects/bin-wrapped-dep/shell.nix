{ npmlock2nix, libwebp, python3 }:
npmlock2nix.shell {
  src = ./.;
  buildInputs = [
    python3 # for node-gyp
    libwebp # cwebp-bin
  ];

  preInstallLinks = {
    "cwebp-bin"."vendor/cwebp" = "${libwebp}/bin/cwebp";
  };
}
