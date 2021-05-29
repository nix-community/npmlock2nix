# npmlock2nix
[![CI](https://github.com/Tweag/npmlock2nix/workflows/Tests/badge.svg)](https://github.com/andir/npmlock2nix/actions)

Utilizing npm lockfiles to create Nix expressions for NPM based projects. This
projects aims to provide the following high-level build outputs:

* just the `node_modules` folder (the result of `npm install` or rather `npm ci`),
* a shell expression that sets NODE_PATH to the above `node_modules` so you can work on your projects without running `npm install` (or similar) in your working directory.
* a build (`npm run build` or similar; customizeable) utilizing the previously mentioned generated `node_modules` folder.

The build results are incremental. Meaning that when you build the shell
expression and afterwards the "build" you'll only have to run the build and not
re-install all the node dependencies (which can take minutes).

# Usage as Shell

Put the following in your `shell.nix`:

```nix
{ pkgs ? import <nixpkgs> {}, nodelock2nix ? <FIXME> { inherit pkgs; } }:
npmlock2nix.shell {
  src = ./.;
  nodejs = pkgs.nodejs-14_x;
  # node_modules_mode = "symlink", (default; or "copy")
  # You can override attributes passed to `node_modules` by setting
  # `node_modules_attrs` like below.
  # A few attributes (such as `nodejs` and `src`) are always inherited from the
  # shell's arguments but can be overriden.
  # node_modules_attrs = {
  #   buildInputs = [ pkgs.libwebp ];
  # };
}
```

# Building the project

FIXME: There are two kinds of "projects". The first kind is where you package an application and the second kind is where you generate some JS, HTML, CSS, … through node.
FIXME: Currently this is targeting (mostly) the second class of builds. The first class is what node2nix does and we should have something compatible.

Put the following in your `shell.nix`:

```nix
{ pkgs ? import <nixpkgs> {}, nodelock2nix ? <FIXME> { inherit pkgs; } }:
npmlock2nix.build {
  src = ./.; # mandatory
  installPhase = "cp -r dist $out"; # mandatory
  # optionally:
  # buildCommands = [ "npm run build" ];
  # node_modules_mode = "symlink", (default; or "copy")
  # You can override attributes passed to `node_modules` by setting
  # `node_modules_attrs` like below.
  # A few attributes (such as `nodejs` and `src`) are always inherited from the
  # shell's arguments but can be overriden.
  # node_modules_attrs = {
  #   buildInputs = [ pkgs.libwebp ];
  # };
}
```

# Building the `node_modules` folder

Sometimes it is easier to hand-roll your projects build phase instead of
reusing something that is not flexible enough or where the author didn't
envision your use-case. Thus making just the `node_modules` folder (and it's
transitive dependencies?) available is desireable.

It also is a logical step for the other use cases as they will have to do this
anyway. Having one derivation that produces the required node closure reduces
the build times when both shell and package build are used. It also allows
rebuilding the project (with the same dependencies) quicker.


```nix
{ pkgs ? import <nixpkgs> {}, nodelock2nix ? <FIXME> { inherit pkgs; } }:
npmlock2nix.node_modules {
  src = ./.;
  # buildInputs = [ … ];

  # You can symlink files into the directory of a specific dependency using the
  # preInstallLinks attribute. Below you see how you can create a link to the
  # cwebp binary at `node_modules/cwebp-bin/cwebp`.
  # preInstallLinks = {
  #   "cwebp-bin" = {
  #       "vendor/cweb-bin" = "${pkgs.libwebp}/bin/cwebp"
  #   };
  # };

  # You can run arbitrary shell operation for given module in given version,
  # using preInstallCustomCommands attribute. Below you see how you can
  # override path to esbuild module, depending on which version in needed.
  # This approach may come in handy, if node_modules should have 2 competing versions
  # of the same module.
  # preInstallCustomCommands = {}: ''
  #   if [ "$npm_package_name@$npm_package_version" == "esbuild@0.8.57" ]; then
  #     sed -i -e 's|process.env.ESBUILD_BINARY_PATH|"${esbuild_0_8_57}/bin/esbuild"|g' ./install.js
  #   elif [ "$npm_package_name@$npm_package_version" == "esbuild@0.11.12" ]; then
  #     sed -i -e 's|process.env.ESBUILD_BINARY_PATH|"${esbuild_0_11_12}/bin/esbuild"|g' ./install.js
  #   fi
  # '';

  # You can set any desired environment by just adding them to this set just
  # like you would do in a regular `stdenv.mkDerivation` invocation:
  # MY_ENVIRONMENT_VARIABLE = "foo";
}
```

