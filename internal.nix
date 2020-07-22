{ nodejs, stdenv, mkShell, lib, fetchurl, writeText }:
rec {
  default_nodejs = nodejs;

  # Description: Turns an npm lockfile dependency into an attribute set as needed by fetchurl
  # Type: String -> Set -> Set
  makeSourceAttrs = name: dependency:
    assert !(dependency ? resolved) -> builtins.throw "Missing `resolved` attribute for dependency `${name}`.";
    assert !(dependency ? integrity) -> builtins.throw "Missing `integrity` attribute for dependency `${name}`.";
    {
      url = dependency.resolved;
      # FIXME: for backwards compatibility we should probably set the
      #        `sha1`, `sha256`, `sha512` … attributes depending on the string
      #        content.
      hash = dependency.integrity;
    };

  # Description: Turns an npm lockfile dependency into a fetchurl derivation
  # Type: String -> Set -> Derivation
  makeSource = name: dependency:
    assert (builtins.typeOf name != "string") -> builtins.throw "Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf dependency != "set") -> builtins.throw "Specification of dependency ${toString name} must be a set";
    fetchurl (makeSourceAttrs name dependency);

  # Description: Parses the lock file as json and returns an attribute set
  # Type: Path -> Set
  readLockfile = file:
    let
      content = builtins.readFile file;
      json = builtins.fromJSON content;
    in
    assert builtins.typeOf json != "set" -> throw "The NPM lockfile must be a valid JSON object";
    # if a lockfile doesn't declare dependencies ensure that we have an empty
    # set. This makes the consuming code eaiser.
    if json ? dependencies then json else json // { dependencies = { }; };


  # Description: Patches a single dependency (recursively) by replacing the resolved URL with a store path
  # Type: String -> Set -> Set
  patchDependency = name: spec:
    assert (builtins.typeOf name != "string") -> builtins.throw "Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf spec != "set") -> builtins.throw "Spec of dependency ${toString name} must be a set";
    spec // {
      resolved = "file://" + (toString (makeSource name spec));
    } // lib.optionalAttrs (spec ? dependencies) {
      dependencies = lib.mapAttrs patchDependency spec.dependencies;
    };

  # Description: Takes a Path to a lockfile and returns the patched version as attribute set
  # Type: Path -> Set
  patchLockfile = file:
    assert (builtins.typeOf file != "path") -> builtins.throw "file ${toString file} must a path";
    let content = readLockfile file; in
    content // {
      dependencies = lib.mapAttrs patchDependency content.dependencies;
    };

  # Description: Takes a Path to a lockfile and returns the patched version as file in the Nix store
  # Type: Path -> Derivation
  patchedLockfile = file: writeText "packages-lock.json" (builtins.toJSON (patchLockfile file));

  node_modules =
    { src
    , packageJson ? src + "/package.json"
    , packageLockJson ? src + "/package-lock.json"
    , buildInputs ? [ ]
    , nativeBuildInputs ? [ ]
    , nodejs ? default_nodejs
    , ...
    }@args:
    let
      lockfile = readLockfile packageLockJson;
    in
    stdenv.mkDerivation {
      inherit (lockfile) version;
      pname = lockfile.name;
      inherit src buildInputs;

      nativeBuildInputs = nativeBuildInputs ++ [
        nodejs
      ];

      preConfigure = ''
        export HOME=$(mktemp -d)
      '';

      postPatch = ''
        ln -sf ${patchedLockfile packageLockJson} package-lock.json
      '';

      buildPhase = ''
        npm ci --offline
      '';
      installPhase = ''
        mkdir $out
        set -x
        if test -d node_modules; then
          mv node_modules $out/
        fi
      '';

      passthru = {
        inherit nodejs;
      };
    };

  shell = attrs:
    let
      nm = node_modules attrs;
    in
    mkShell {
      buildInputs = [ nm.nodejs ];
      shellHook = ''
        export NODE_PATH="${nm}/node_modules:$NODE_PATH"
      '';
      passthru.node_modules = nm;
    };

  build = attrs:
    let nm = node_modules attrs; in
    { };
}
