{ nodejs, stdenv, mkShell, lib, fetchurl, writeText, writeTextFile, runCommand }:
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

  # Turn a derivation (with name & src attribute) into a directory containing the unpacked sources
  # Type: Derivation -> Derivation
  nodeSource = nodes: runCommand "node-sources-${nodejs.version}"
    { } ''
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
    , preInstallLinks ? { } # set that describes which files should be linked in a specific packages folder
    , ...
    }@args:
    let
      lockfile = readLockfile packageLockJson;

      preinstall_node_modules = writeTextFile {
        name = "prepare";
        destination = "/node_modules/.hooks/prepare";
        text = ''
          #! ${stdenv.shell}

          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: mappings: ''
                if [ "$npm_package_name" == "${name}" ]; then
                ${lib.concatStringsSep "\n"
                  (lib.mapAttrsToList (to: from: ''
                        dirname=$(dirname ${to})
                        mkdir -p $dirname
                        ln -s ${from} ${to}
                      '') mappings
                  )}
                fi
              '') preInstallLinks
            )}

          if grep -I -q -r '/bin/' .; then
            source $stdenv/setup
            patchShebangs .
          fi

        '';
        executable = true;
      };
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

      setupHooks = [
        ./set-node-path.sh
      ];

      preConfigure = ''
        export HOME=$(mktemp -d)
      '';

      postPatch = ''
        ln -sf ${patchedLockfile packageLockJson} package-lock.json
      '';

      buildPhase = ''
        runHook preBuild
        mkdir -p node_modules/.hooks
        ln -s ${preinstall_node_modules}/node_modules/.hooks/prepare node_modules/.hooks/preinstall
        npm install --offline --nodedir=${nodeSource nodejs}
        test -d node_modules/.bin && patchShebangs node_modules/.bin
        rm -rf node_modules/.hooks
        runHook postBuild
      '';
      installPhase = ''
        mkdir $out

        if test -d node_modules; then
          if [ $(ls -1 node_modules | wc -l) -gt 0 ] || [ -e node_modules/.bin ]; then
            mv node_modules $out/
            if test -d $out/node_modules/.bin; then
              ln -s $out/node_modules/.bin $out/bin
            fi
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
    , copy_node_modules ? false
    , buildBuildInputs ? [ ]
    , ...
    }@attrs:
    let
      nm = node_modules (builtins.removeAttrs attrs [ "buildBuildInputs" "copy_node_modules" "npmCommands" "installPhase" ]);
    in
    stdenv.mkDerivation {
      pname = nm.pname;
      version = nm.version;
      buildInputs = [ nm ] ++ buildBuildInputs;

      postUnpack =
        if !copy_node_modules && symlink_node_modules then ''
          ln -sf ${nm}/node_modules node_modules
          export NODE_PATH="$(pwd)/node_modules:$NODE_PATH"
        '' else if copy_node_modules then ''
          cp -r ${nm}/node_modules node_modules
          chmod -R u+rw node_modules
          export NODE_PATH="$(pwd)/node_modules:$NODE_PATH"
        '' else "";

      buildPhase = ''
        runHook preBuild
        ${lib.concatStringsSep "\n" npmCommands}
        runHook postBuild
      '';
      inherit src installPhase;
    };
}
