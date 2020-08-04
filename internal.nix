{ nodejs, stdenv, mkShell, lib, fetchurl, writeText, writeTextFile, runCommand }:
rec {
  default_nodejs = nodejs;

  # Description: Turns an npm lockfile dependency into an attribute set as needed by fetchurl
  # Type: String -> Set -> Set
  makeSourceAttrs = name: dependency:
    assert !(dependency ? resolved) -> throw "[npmlock2nix] Missing `resolved` attribute for dependency `${name}`.";
    assert !(dependency ? integrity) -> throw "[npmlock2nix] Missing `integrity` attribute for dependency `${name}`.";
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
    assert (builtins.typeOf name != "string") -> throw "[npmlock2nix] Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf dependency != "set") -> throw "[npmlock2nix] Specification of dependency ${toString name} must be a set";
    if dependency ? resolved && dependency ? integrity then
      fetchurl (makeSourceAttrs name dependency)
    else throw "[npmlock2nix] A valid dependency consists of at least the resolved and integrity field. Missing one or both of them for `${name}`.";

  # Description: Parses the lock file as json and returns an attribute set
  # Type: Path -> Set
  readLockfile = file:
    let
      content = builtins.readFile file;
      json = builtins.fromJSON content;
    in
    assert builtins.typeOf json != "set" -> throw "[npmlock2nix] The NPM lockfile must be a valid JSON object";
    # if a lockfile doesn't declare dependencies ensure that we have an empty
    # set. This makes the consuming code eaiser.
    if json ? dependencies then json else json // { dependencies = { }; };


  # Description: Patches a single dependency (recursively) by replacing the resolved URL with a store path
  # Type: String -> Set -> Set
  patchDependency = name: spec:
    assert (builtins.typeOf name != "string") -> throw "[npmlock2nix] Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf spec != "set") -> throw "[npmlock2nix] pec of dependency ${toString name} must be a set";
    let
      isBundled = spec ? bundled && spec.bundled == true;
    in
    if lib.hasPrefix "github:" (spec.from or "") || lib.hasPrefix "github:" (spec.source or "") then
      throw "[npmlock2nix] The given package-lock.json contains sources that refer to GitHub. The source spec is often not precise enough to be translated into a (reliable) Nix git fetch invocation."
    else
      (spec // lib.optionalAttrs (!isBundled) ({
        resolved = "file://" + (toString (makeSource name spec));
      }) // lib.optionalAttrs (spec ? dependencies) {
        dependencies = lib.mapAttrs patchDependency spec.dependencies;
      });

  # Description: Takes a Path to a lockfile and returns the patched version as attribute set
  # Type: Path -> Set
  patchLockfile = file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") -> throw "[npmlock2nix] file ${toString file} must be a path or string";
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

  add_node_modules_to_cwd = node_modules: mode:
    ''
      if test -e node_modules; then
        echo '[npmlock2nix] There is already a `node_modules` directory. Not replacing it.' >&2
        exit 1
      fi
    '' +
    (
      if mode == "copy" then ''
        cp --no-preserve=mode -r ${node_modules}/node_modules node_modules
        chmod -R u+rw node_modules
      '' else if mode == "symlink" then ''
        ln -s ${node_modules}/node_modules node_modules
      '' else throw "[npmlock2nix] node_modules_mode must be either `copy` or `symlink`"
    ) + ''
      export NODE_PATH="$(pwd)/node_modules:$NODE_PATH"
    '';

  # Extract the attributes that are relevant for building node_modules and use
  # them as defaults in case the node_modules_attrs attribute doesn't have
  # them.
  # Type: Set -> Set
  get_node_modules_attrs = { node_modules_attrs ? { }, ... }@attrs:
    let
      getAttr = name: from: lib.optionalAttrs (builtins.hasAttr name from) { "${name}" = from.${name}; };
      getAttrs = names: from: lib.foldl (a: b: a // (getAttr b from)) { } names;
    in
    (getAttrs [ "src" "nodejs" ] attrs // node_modules_attrs);

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
      assert (builtins.typeOf preInstallLinks != "set") -> throw "[npmlock2nix] `preInstallLinks` must be an attributeset of attributesets";
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
              source $TMP/preinstall-env
              patchShebangs .
            fi

          '';
          executable = true;
        };

        extraArgs = builtins.removeAttrs args [ "preInstallLinks" ];
      in
      stdenv.mkDerivation (extraArgs // {
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
          declare -pf > $TMP/preinstall-env
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
      });

  shell =
    { node_modules_mode ? "symlink"
    , ...
    }@attrs:
    let
      nm = node_modules (get_node_modules_attrs attrs);
      extraAttrs = builtins.removeAttrs attrs [ "node_modules_attrs" ];
    in
    mkShell ({
      buildInputs = [ nm.nodejs nm ];
      shellHook = ''
        # FIXME: we should somehow register a GC root here in case of a symlink?
        ${add_node_modules_to_cwd nm node_modules_mode}
      '';
      passthru.node_modules = nm;
    } // extraAttrs);

  build =
    { src
    , buildCommands ? [ "npm run build" ]
    , installPhase
    , node_modules_mode ? "symlink"
    , buildInputs ? [ ]
    , ...
    }@attrs:
    let
      nm = node_modules (get_node_modules_attrs attrs);
      extraAttrs = builtins.removeAttrs attrs [ "node_modules_attrs" ];
    in
    stdenv.mkDerivation ({
      pname = nm.pname;
      version = nm.version;
      buildInputs = [ nm ] ++ buildInputs;
      inherit src installPhase;

      preConfigure = add_node_modules_to_cwd nm node_modules_mode;

      buildPhase = ''
        runHook preBuild
        ${lib.concatStringsSep "\n" buildCommands}
        runHook postBuild
      '';
    } // extraAttrs);
}
