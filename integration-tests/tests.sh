#!/usr/bin/env nix-shell
#!nix-shell -p bats -i bats

@test "Require a node dependency inside the shell environment" {
    run nix-shell ./tests/examples-projects/single-dependency/shell.nix --run "node -e 'console.log(require(\"leftpad\")(123, 7));'"

    [ "$status" -eq 0 ]
    [ "$output" = "0000123" ]
}

@test "Set the nodejs version to use to v10 inside the shell environment" {
    run nix-shell ./tests/examples-projects/single-dependency/shell.nix --argstr version "10_x" --run "node -e 'console.log(process.version.split(\".\")[0]);'"

    [ "$status" -eq 0 ]
    [ "$output" = "v10" ]
}
