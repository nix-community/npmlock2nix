#!/usr/bin/env nix-shell
#!nix-shell -I nixpkgs=./nix -i bash

set -e

export XDG_CONFIG_HOME="/foo/bar"

echo -e "Running unit tests\n"
nix-build -A tests --no-build-output --no-out-link --show-trace

echo -e "\n\nRunning integration tests\n"
$(nix-build  -A tests.integration-tests --no-out-link --show-trace)

echo -e "\n\nTest githubSourceHashMap in restricted mode\n"
nix-build tests/examples-projects/github-dependency/default.nix --restrict-eval -I . --allowed-uris 'https://github.com/nixos/nixpkgs' --show-trace
