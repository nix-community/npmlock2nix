# npmlock2nix
[![CI](https://github.com/andir/npmlock2nix/workflows/Tests/badge.svg)](https://github.com/andir/npmlock2nix/actions)

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
}
```

# Building the project

FIXME: There are two kinds of "projects". The first kind is where you package an application and the second kind is where you generate some JS, HTML, CSS, … through node.
FIXME: Currently this is targeting (mostly) the second class of builds. The first class is what node2nix does and we should have something compatible.

Put the following in your `shell.nix`:

```nix
{ pkgs ? import <nixpkgs> {}, nodelock2nix ? <FIXME> { inherit pkgs; } }:
npmlock2nix.build {
  src = ./.;
  # optionally:
  # npmCommands = [ "npm run build" ];
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
}
```

# Contributing

Please feel free to contribute to this repository. We try to take a tests-first
approach to ensure everything works and continues to work as the project
evolves.

We recommend using [`direnv`](https://github.com/direnv/direnv) with this repository.

## Running tests

Simply running the `test.sh` in the root of the repository should be sufficient
to run both unit- and integration-tests.

Within the `nix-shell` environment (either via manually starting `nix-shell` or
via `direnv`) you can execute the `watch-tests` command. It will continuously
watch the existing files and rerun tests on any change.

You can manually build the targets by invoking `nix-build -A tests` and
`nix-build -A tests.integration-tests`. The Nix build of the integration tests
just creates a test driver that executes them via
[Smoke](https://github.com/SamirTalwar/smoke). The generated script is then run
impurely as it targets `nix-shell` behaviour (which is hard to test from within
a nix build).

## Formatting

We are using [`nixpkgs-fmt`](https://github.com/nix-community/nixpkgs-fmt) for
Nix code formatting. While it isn't always the pretties code it is a format
that we did settle on for consistency.

When using the shell expression in this repository pre-commit hooks will be
installed automatically that ensure all comitted code is properly formatted.
