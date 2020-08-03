{ nodejs, stdenv, mkShell, lib, fetchurl, writeText, runCommand }:
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
    let
      isBundled = spec ? bundled && spec.bundled == true;
    in
    spec // lib.optionalAttrs (!isBundled) ({
      resolved = "file://" + (toString (makeSource name spec));
    }) // lib.optionalAttrs (spec ? dependencies) {
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

  # Prepared source for npm installation
  nodeSource = nodes: runCommand "node-sources-${nodejs.version}" {} ''
    tar --no-same-owner --no-same-permissions -xf ${nodejs.src}
    mv node-* $out
  '';

  node_modules =
    { src
    , packageJson ? src + "/package.json"
    , packageLockJson ? src + "/package-lock.json"
    , buildInputs ? [ ]
    , nativeBuildInputs ? [ ]
    , nodejs ? default_nodejs
    , preBuild ? ""
    , postBuild ? ""
    , ...
    }@args:
    let
      lockfile = readLockfile packageLockJson;
    in
    stdenv.mkDerivation {
      inherit (lockfile) version;
      pname = lockfile.name;
      inherit src buildInputs preBuild postBuild;

      nativeBuildInputs = nativeBuildInputs ++ [
        nodejs
      ];

      propagatedBuildInputs = [
        nodejs
      ];

      preConfigure = ''
        export HOME=$(mktemp -d)
      '';

      postPatch = ''
        ln -sf ${patchedLockfile packageLockJson} package-lock.json
      '';

      buildPhase = ''
        runHook preBuild
        npm ci --offline --nodedir=${nodeSource nodejs}
        runHook postBuild
      '';
      installPhase = ''
        mkdir $out
        if test -d node_modules; then
          mv node_modules $out/
          if test -d $out/node_modules/.bin; then
            ln -s $out/node_modules/.bin $out/bin
          fi
        fi
      '';

      passthru = {
        inherit nodejs;
      };
    };

  shell =
    { symlink_node_modules ? true
    , ...
    }@attrs:
    let
      nm = node_modules attrs;
    in
    mkShell {
      buildInputs = [ nm.nodejs nm ];
      shellHook = ''
        export NODE_PATH="${nm}/node_modules:$NODE_PATH"
      '' + (lib.optionalString symlink_node_modules ''
        if test -d node_modules; then
          echo '[npmlock2nix] There is already a `node_modules` directory. Not replacing it.' >&2
          exit 1
        fi

        # FIXME: we should somehow register a GC root here?
        ln -sf ${nm}/node_modules node_modules
      ''
      );
      passthru.node_modules = nm;
    };

  build =
    { src
    , npmCommands
    , installPhase
    , symlink_node_modules ? true
    , ...
    }@attrs:
    let
      nm = node_modules attrs;
    in
    stdenv.mkDerivation {
      pname = nm.pname;
      version = nm.version;
      buildInputs = [ nm ];

      postUnpack = ''
        ln -sf ${nm}/node_modules node_modules
      '';

      buildPhase = ''
        runHook preBuild
        ${lib.concatStringsSep "\n" npmCommands}
        runHook postBuild
      '';
      inherit src installPhase;
    };
}
