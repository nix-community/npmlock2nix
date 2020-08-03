#!/usr/bin/env nix-shell
#!nix-shell -I nixpkgs=./nix -p nix -i bash

set -e

export XDG_CONFIG_HOME="/foo/bar"

echo -e "Running unit tests\n"
nix-build -A tests --no-build-output --no-out-link

echo -e "\n\nRunning integration tests\n"
$(nix-build  -A tests.integration-tests --no-out-link)
