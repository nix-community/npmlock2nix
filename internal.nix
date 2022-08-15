{ nodejs-14_x, jq, openssl, coreutils, stdenv, mkShell, lib, fetchurl, writeText, writeShellScript, runCommand, fetchFromGitHub }:
rec {
  default_nodejs = nodejs-14_x;

  SENTINEL_VALUE = builtins.hashString "sha1" (toString ./.);

  # builtins.fetchGit wrapper that ensures compatibility with Nix 2.3 and Nix 2.4
  # Type: Attrset -> Path
  fetchGitWrapped =
    let
      is24OrNewer = lib.versionAtLeast builtins.nixVersion "2.4";
    in
    if is24OrNewer then
    # remove the now unsupported / insufficient `ref` paramter
      args: builtins.fetchGit (builtins.removeAttrs args [ "ref" ])
    else
    # for 2.3 (and older?) we remove the unsupported `allRefs` parameter
      args: builtins.fetchGit (builtins.removeAttrs args [ "allRefs" ])
  ;

  # Description: Custom throw function that ensures our error messages have a common prefix.
  # Type: String -> Throw
  throw = str: builtins.throw "[npmlock2nix] ${str}";

  # Description: Turns an npm lockfile dependency into an attribute set as needed by fetchurl
  # Type: String -> Set -> Set
  makeSourceAttrs = name: dependency:
    assert !(dependency ? resolved) -> throw "Missing `resolved` attribute for dependency `${name}`.";
    assert !(dependency ? integrity) -> throw "Missing `integrity` attribute for dependency `${name}`.";
    {
      url = dependency.resolved;
      # FIXME: for backwards compatibility we should probably set the
      #        `sha1`, `sha256`, `sha512` … attributes depending on the string
      #        content.
      hash = dependency.integrity;
    };

  # Description: Checks if a string looks like a valid git revision
  # Type: String -> Boolean
  isGitRev = str:
    (builtins.match "[0-9a-f]{40}" str) != null;

  # Description: Takes a string of the format "github:org/repo#revision" and returns
  # an attribute set { org, repo, rev }
  # Type: String -> Set
  parseGitHubRef = str:
    let
      parts = builtins.split "[:#/]" str;
    in
    assert !(builtins.length parts == 7) ->
      throw "failed to parse GitHub reference `${str}`. Expected a string of format `github:org/repo#revision`";
    rec {
      inherit parts;
      org = builtins.elemAt parts 2;
      repo = builtins.elemAt parts 4;
      rev = builtins.elemAt parts 6;
    };

  # Description: Takes an attribute set describing a git dependency and returns
  # a .tgz of the repository as store path. If the attribute hash contains a
  # hash attribute it will provide the value to `fetchFromGitHub` which will
  # also work in restricted evaluation.
  # Type: Set -> Path
  buildTgzFromGitHub = { name, org, repo, rev, ref, hash ? null, sourceOptions ? { } }:
    let
      src =
        if hash != null then
          fetchFromGitHub
            {
              owner = org;
              inherit repo;
              inherit rev;
              sha256 = hash; # FIXME: what if sha3?
            } else
          fetchGitWrapped {
            url = "https://github.com/${org}/${repo}";
            inherit rev ref;
            allRefs = true;
          };

      sourceInfo = {
        github = { inherit org repo rev ref; };
      };
      drv = packTgz sourceOptions.nodejs name ref src;
    in
    if sourceOptions ? sourceOverrides.${name}
    then sourceOptions.sourceOverrides.${name} sourceInfo drv
    else drv;

  # Description: Packs a source directory into a .tgz tar archive. If the
  # source is an archive, it gets unpacked first.
  # Type: Path -> String -> String -> Path -> Path
  packTgz = nodejs: pname: version: src: stdenv.mkDerivation (
    let
      preInstallLinks = writeShellScript "preInstallLinks" ''
        for link in "$(<preinstalled.links)"; do
          if [ ! -z "$link" ]; then
            ln -sf $link
          fi
        done
      '';
    in
    rec {
      name = lib.strings.sanitizeDerivationName "${pname}-${version}.tgz";
      id = "id_" + (builtins.replaceStrings [ "-" "." ] [ "_" "_" ] name);

      phases = "unpackPhase patchPhase installPhase";

      inherit src;
      sourceRoot = "package";
      outputs = [ "out" "hash" ];
      nativeBuildInputs = [ jq openssl ];

      unpackPhase = ''
        runHook preUnpack
        mkdir -p ${sourceRoot}
        [[ -d ${src} ]] && cp -RT --reflink=auto ${src} ${sourceRoot}
        [[ -f ${src} ]] && tar --no-same-owner --strip-components=1 --warning=no-timestamp -xf ${src} -C ${sourceRoot}
        runHook postUnpack
      '';

      installPhase = ''
        function prepare_links_for_npm_preinstall() {
          find . -type l -exec readlink -nf "{}" \; -exec echo " {}" \; -exec false {} \+ > preinstalled.links || {
            cp -p ${preInstallLinks} npm-preinstall-links.sh
            jq -r '.scripts.preinstall as $preinstall | .scripts.preinstall = "./npm-preinstall-links.sh;" + $preinstall' \
             package.json > package.json.tmp && mv package.json.tmp package.json
          }
        }

        function patch_node_package_bin() {
          for bin in $(jq -r '.bin | (.[]?, (select(.|type=="string")|.))' package.json); do
            if [ -f $bin ]; then
              chmod 755 $bin
              sed --follow-symlinks -i 's,#![[:space:]]*/usr/bin/env ,#!${coreutils}/bin/env ,' $bin
            fi
          done
        }

        prepare_links_for_npm_preinstall
        patch_node_package_bin

        runHook preInstall
        tar -C . -czf $out ./
        echo sha512-$(openssl dgst -sha512 -binary $out | openssl base64 -A) > $hash
        runHook postInstall
      '';
    }
  );

  # Description: Turns a dependency with a from field of the format
  # `github:org/repo#revision` into a git fetcher. The fetcher can
  # receive a hash value by calling 'sourceHashFunc' if a source hash
  # map has been provided. Otherwise the function yields `null`. Patches
  # specified with sourceOverrides will be applied
  # Type: { sourceHashFunc :: Fn } -> String -> Set -> Path
  makeGithubSource = sourceOptions@{ sourceHashFunc, ... }: name: dependency:
    assert !(dependency ? version) ->
      builtins.throw "version` attribute missing from `${name}`";
    assert (lib.hasPrefix "github: " dependency.version) -> builtins.throw "invalid prefix for `version` field of `${name}` expected `github:`, got: `${dependency.version}`.";
    let
      v = parseGitHubRef dependency.version;
      f = parseGitHubRef dependency.from;
    in
    assert v.org != f.org -> throw "version and from of `${name}` disagree on the GitHub org to fetch from: `${v.org}` vs `${f.org}`";
    assert v.repo != f.repo -> throw "version and from of `${name}` disagree on the GitHub repo to fetch from: `${v.repo}` vs `${f.repo}`";
    assert !isGitRev v.rev -> throw "version of `${name}` does not specify a valid git rev: `${v.rev}`";
    let
      src = buildTgzFromGitHub {
        inherit name;
        ref = f.rev;
        inherit (v) org repo rev;
        hash = sourceHashFunc { type = "github"; value = v; };
        inherit sourceOptions;
      };
    in
    {
      json =
        (builtins.removeAttrs dependency [ "from" ]) // {
          version = "0.0." + (builtins.substring 0 16 (lib.replaceStrings [ "a" "b" "c" "d" "e" "f" ] [ "10" "11" "12" "13" "14" "15" ] f.rev));
          resolved = "file://" + (toString src);
          integrity = "@${src.id}@";
        };
      pkg = src;
    };

  # Description: Checks if the given string looks like a vila HTTP or HTTPS url
  # Type: String -> Bool
  looksLikeUrl = s:
    assert (builtins.typeOf s != "string") -> throw "can only check strings if they are URL-like";
    lib.hasPrefix "http://" s || lib.hasPrefix "https://" s;

  # Description: Checks the given dependency spec if its version field should
  # be used as URL in absence of a resolved attribute. In some cases the
  # resolved field is missing but the version field contains a valid URL.
  # Type: Set -> Bool
  shouldUseVersionAsUrl = dependency:
    dependency ? version && dependency ? integrity && ! (dependency ? resolved) && looksLikeUrl dependency.version;

  # Description: Replaces the `resolved` field of a dependency with a
  # prefetched version from the Nix store. Patches specified with sourceOverrides
  # will be applied, in which case the `integrity` attribute is set to `null`,
  # in order to be recomputer later
  # Type: { sourceOverrides :: Fn, nodejs :: Package } -> String -> Set -> Set
  makeUrlSource = { sourceOverrides ? { }, nodejs, ... }: name: dependency:
    let
      src = fetchurl (makeSourceAttrs name dependency);
      sourceInfo = {
        inherit (dependency) version;
      };
      drv = packTgz nodejs name dependency.version src;
      tgz = (
        if sourceOverrides ? ${name} then
        # If we have modification to this source, unpack the tgz, apply the
        # patches and repack the tgz
          sourceOverrides.${name} sourceInfo drv
        else
          if sourceOverrides.buildRequirePatchShebangs or false == node_modules.buildRequirePatchShebangs then drv else src
      );
    in
    {
      json = dependency // {
        resolved = "file://" + (toString tgz);
      } // lib.optionalAttrs (tgz != src) {
        # Integrity was tampered with due to the source attributes, so it needs
        # to be recalculated, which is done in the node_modules builder
        integrity = "@${tgz.id}@";
      };
      pkg = tgz;
    };

  # Description: Turns an npm lockfile dependency into a fetchurl derivation
  # Type: { sourceHashFunc :: Fn } -> String -> Set -> Derivation
  makeSource = sourceOptions: name: dependency:
    assert (builtins.typeOf name != "string") ->
      throw "Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf dependency != "set") ->
      throw "Specification of dependency ${toString name} must be a set";
    if dependency ? resolved && dependency ? integrity then
      makeUrlSource sourceOptions name dependency
    else if dependency ? from && dependency ? version then
      makeGithubSource sourceOptions name dependency
    else if shouldUseVersionAsUrl dependency then
      makeSource sourceOptions name (dependency // { resolved = dependency.version; })
    else throw "A valid dependency consists of at least the resolved and integrity field. Missing one or both of them for `${name}`. The object I got looks like this: ${builtins.toJSON dependency}";

  # Description: Parses the lock file as json and returns an attribute set
  # Type: Path -> Set
  readPackageLikeFile = file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") ->
      throw "file ${toString file} must be a path or string";
    let
      content = builtins.readFile file;
      json = builtins.fromJSON content;
    in
    assert
    builtins.typeOf json != "set" ->
    throw "The NPM lockfile must be a valid JSON object";
    # if a lockfile doesn't declare dependencies ensure that we have an empty
    # set. This makes the consuming code eaiser.
    if json ? dependencies then json else json // { dependencies = { }; };

  # Description: Turns a github string reference into a store path with a tgz of the reference
  # Type: Fn -> String -> String -> Path
  stringToTgzPath = sourceOptions@{ sourceHashFunc, ... }: name: str:
    let
      gitAttrs = parseGitHubRef str;
    in
    buildTgzFromGitHub {
      name = "${name}.tgz";
      ref = gitAttrs.rev;
      inherit (gitAttrs) org repo rev;
      hash = sourceHashFunc { type = "github"; value = gitAttrs; };
      inherit sourceOptions;
    };

  # Description: Patch the `requires` attributes of a dependency spec to refer to paths in the store
  # Type: { sourceHashFunc :: Fn } -> String -> Set -> Set
  patchRequires = sourceOptions: name: requires:
    let
      patchReq = name: version: if lib.hasPrefix "github:" version then stringToTgzPath sourceOptions name version else version;
    in
    lib.mapAttrs patchReq requires;


  # Description: Patches a single lockfile dependency (recursively) by replacing the resolved URL with a store path
  # Type: { sourceHashFunc :: Fn } -> String -> Set -> { result :: Set, deps :: List }
  patchDependency = sourceOptions: raw_name: spec:
    assert (builtins.typeOf raw_name != "string") ->
      throw "Name of dependency ${toString raw_name} must be a string";
    let
      name = genericPackageName raw_name;
      isBundled = spec ? bundled && spec.bundled == true;
      patchSource = if !isBundled then (makeSource sourceOptions name spec) else { json = { }; };
      hasGitHubRequires = spec: (spec ? requires) && (lib.any (x: lib.hasPrefix "github:" x) (lib.attrValues spec.requires));
      patchRequiresSources = lib.optionalAttrs (hasGitHubRequires spec) { requires = (patchRequires sourceOptions name spec.requires); };
      nestedDependencies = lib.mapAttrs (name: patchDependency sourceOptions name) spec.dependencies;
      patchDependenciesSources = lib.optionalAttrs (spec ? dependencies) { dependencies = lib.mapAttrs (_: value: value.result) nestedDependencies; };
      nestedDeps = lib.optionals (spec ? dependencies) (lib.concatMap (value: value.deps) (lib.attrValues nestedDependencies));
      deps = [ patchSource.pkg ] ++ nestedDeps;

      # For our purposes we need a dependency with
      # - `resolved` set to a path in the nix store (`patchSource`)
      # - All `requires` entries of this dependency that are set to github URLs set to a path in the nix store (`patchRequiresSources`)
      # - This needs to be done recursively for all `dependencies` in the lockfile (`patchDependenciesSources`)
      result = spec // patchSource.json // patchRequiresSources // patchDependenciesSources;
    in
    if builtins.typeOf spec == "set" then {
      inherit result deps;
    } else {
      result = if spec == "latest" then sourceOptions.packagesVersions.${name}.version else spec;
      deps = [ ];
    };

  genericPackageName = name:
    (lib.last (lib.strings.splitString "node_modules/" name));

  mostRecentPackagesVersion = deps1: deps2:
    let
      base_deps = lib.mapAttrs' (name: value: { name = genericPackageName name; value = { version = value.version; }; }) deps1;
    in
    base_deps // (lib.mapAttrs'
      (raw_name: value:
        let
          name = genericPackageName raw_name;
          super = base_deps.${name} or { version = "0"; };
        in
        {
          inherit name; value =
          super // (
            lib.optionalAttrs (builtins.compareVersions super.version value.version == -1)
              { version = value.version; }
          );
        }
      )
      deps2);

  # Description: Takes a Path to a lockfile and returns the patched version as attribute set
  # Type: { sourceHashFunc :: Fn } -> Path -> { result :: Set, integrityUpdates :: List { path, file } }
  patchLockfile = sourceOptions: content:
    let
      dependencies = lib.mapAttrs (name: patchDependency sourceOptions name) content.dependencies;
      packages = lib.mapAttrs
        (name:
          if name != "" then
            (patchDependency sourceOptions name)
          else value: {
            result = value;
          })
        content.packages;
    in
    {
      result = content // {
        dependencies = lib.mapAttrs (_: value: value.result) dependencies;
      } // lib.optionalAttrs (content ? packages) {
        packages = lib.mapAttrs (_: value: value.result) packages;
      };
      deps = lib.concatMap (value: value.deps) (lib.attrValues dependencies);
    };

  # Description: Rewrite all the `github:` references to wildcards.
  # Type: Path -> Set
  patchPackagefile = sourceOptions: content:
    let
      patchDep = (name: version:
        # If the dependency is of the form github:owner/repo#branch the package-lock.json contains the specific
        # revision that the branch was pointing at at the time of npm install.
        # The package.json itself does not contain enough information to resolve a specific dependency,
        # because it only contains the branch name. Therefore we cannot substitute with a nix store path.
        # If we leave the dependency unchanged, npm will try to resolve it and fail. We therefore substitute with a
        # wildcard dependency, which will make npm look at the lockfile.
        if lib.hasPrefix "github:" version then
          "*"
        else if version == "latest" then sourceOptions.packagesVersions.${name}.version else version);
      dependencies = if (content ? dependencies) then lib.mapAttrs patchDep content.dependencies else { };
      devDependencies = if (content ? devDependencies) then lib.mapAttrs patchDep content.devDependencies else { };
    in
    content // { inherit devDependencies dependencies; };

  # Description: Takes a Path to a package file and returns the patched version as file in the Nix store
  # Type: Path -> Derivation
  patchedPackagefile = sourceOptions: file: writeText "package.json"
    (
      builtins.toJSON (patchPackagefile sourceOptions file)
    );

  # Description: Takes a Path to a lockfile and returns the patched version as file in the Nix store
  # Type: { sourceHashFunc :: Fn } -> Path
  patchedLockfile = sourceOptions: file:
    let
      patched = patchLockfile sourceOptions file;
      replacement = writeText "packages_hashes.sed" (lib.concatMapStrings
        (dep: lib.optionalString (dep ? id) ''
          s @${dep.id}@ ${lib.removeSuffix "\n" (builtins.readFile dep.hash)} g;
        ''
        )
        patched.deps);
      package-lock-json = writeText "package-lock.json" (builtins.toJSON patched.result);
    in
    stdenv.mkDerivation ({
      name = "package-lock.json";
      phases = [ "patchPhase" ];

      postPatch = ''
        sed -f ${replacement} ${package-lock-json} > $out
      '';
    });


  # Description: Turn a derivation (with name & src attribute) into a directory containing the unpacked sources
  # Type: Derivation -> Derivation
  nodeSource = nodejs: runCommand "node-sources-${nodejs.version}"
    { } ''
    tar --no-same-owner --no-same-permissions -xf ${nodejs.src}
    mv node-* $out
  '';

  # Description: Creates shell scripts to provide node_modules to the environment supporting
  # two different modes: "symlink" and "copy"
  # Type: Derivation -> String -> String
  add_node_modules_to_cwd = node_modules: mode:
    ''
      # If node_modules is a managed symlink we can safely remove it and install a new one
      ${lib.optionalString (mode == "symlink") ''
        if [[ "$(readlink -f node_modules)" == ${builtins.storeDir}* ]]; then
          rm -f node_modules
        fi
      ''}

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
      '' else throw "node_modules_mode must be either `copy` or `symlink`"
    ) + ''
      export NODE_PATH="$(pwd)/node_modules:$NODE_PATH"
    '';

  # Description: Extract the attributes that are relevant for building node_modules and use
  # them as defaults in case the node_modules_attrs attribute doesn't have
  # them.
  # Type: Set -> Set
  get_node_modules_attrs = { node_modules_attrs ? { }, ... }@attrs:
    let
      getAttr = name: from: lib.optionalAttrs (builtins.hasAttr name from) { "${name}" = from.${name}; };
      getAttrs = names: from: lib.foldl (a: b: a // (getAttr b from)) { } names;
    in
    (getAttrs [ "src" "nodejs" ] attrs // node_modules_attrs);

  # Description: Takes a dependency spec and a map of github sources/hashes and returns either the map or 'null'
  # Type: Set -> Set -> Set | null
  sourceHashFunc = githubSourceHashMap: spec:
    if spec.type == "github" then
      lib.attrByPath
        [ spec.value.org spec.value.repo spec.value.rev ]
        (
          lib.traceSeq
            "[npmlock2nix] warning: missing attr in githubSourceHashMap: ${spec.value.org}.${spec.value.repo}.${spec.value.rev}"
            null
        )
        githubSourceHashMap
    else
      throw "sourceHashFunc: spec.type '${spec.type}' is not supported. Supported types: 'github'";

  node_modules =
    {
      __functor = self: { src
                        , packageJson ? src + "/package.json"
                        , packageLockJson ? src + "/package-lock.json"
                        , buildInputs ? [ ]
                        , nativeBuildInputs ? [ ]
                        , nodejs ? default_nodejs
                        , preBuild ? ""
                        , postBuild ? ""
                        , preInstallLinks ? null
                        , sourceOverrides ? { }
                        , githubSourceHashMap ? { }
                        , passthru ? { }
                        , ...
                        }@args:
        assert (preInstallLinks != null) ->
          throw "`preInstallLinks` was removed use `sourceOverrides";
        let
          cleanArgs = builtins.removeAttrs args [ "src" "packageJson" "packageLockJson" "buildInputs" "nativeBuildInputs" "nodejs" "preBuild" "postBuild" "sourceOverrides" "githubSourceHashMap" ];
          lockfile = readPackageLikeFile packageLockJson;
          packagefile = readPackageLikeFile packageJson;

          sourceOptions = {
            sourceHashFunc = sourceHashFunc githubSourceHashMap;
            inherit nodejs sourceOverrides;
            packagesVersions = mostRecentPackagesVersion lockfile.dependencies lockfile.packages or { };
          };

          allDependenciesNames = builtins.attrNames (packagefile.dependencies // packagefile.devDependencies or { });

          patchedLockfilePath = patchedLockfile sourceOptions lockfile;
          patchedPackagefilePath = patchedPackagefile sourceOptions packagefile;
        in
        assert lockfile.lockfileVersion == 2 && lib.versionOlder nodejs.version "15.0"
          -> throw "npm lockfile V2 require nodejs version >= 15, it is not supported by nodejs ${nodejs.version}";
        stdenv.mkDerivation ({
          pname = lib.strings.sanitizeDerivationName lockfile.name;
          version = lockfile.version or "0";
          dontUnpack = true;

          inherit nativeBuildInputs buildInputs preBuild postBuild;
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
            ln -sf ${patchedLockfilePath} package-lock.json
            ln -sf ${patchedPackagefilePath} package.json
          '';

          buildPhase = ''
            runHook preBuild
            export HOME=.
            npm ci --offline --nodedir=${nodeSource nodejs} --ignore-scripts
            npm rebuild --offline --nodedir=${nodeSource nodejs} ${builtins.concatStringsSep " " allDependenciesNames}
            test -d node_modules/.bin && patchShebangs node_modules/.bin
            runHook postBuild
          '';
          installPhase = ''
            mkdir "$out"

            if test -d node_modules; then
              if [ $(ls -1 node_modules | wc -l) -gt 0 ] || [ -e node_modules/.bin ]; then
                mv node_modules $out/
                if test -d $out/node_modules/.bin; then
                  ln -s $out/node_modules/.bin $out/bin
                fi
              fi
            fi
          '';

          passthru = passthru // {
            inherit nodejs;
            lockfile = patchedLockfilePath;
            packagesfile = patchedPackagefilePath;
          };
        } // cleanArgs);
      packageRequirePatchShebangs = sourceInfo: drv: drv;
      buildRequirePatchShebangs = SENTINEL_VALUE;
    };

  shell =
    { src
    , node_modules_mode ? "symlink"
    , node_modules_attrs ? { }
    , buildInputs ? [ ]
    , passthru ? { }
    , shellHook ? ""
    , ...
    }@attrs:
    let
      nm = node_modules (get_node_modules_attrs attrs);
      extraAttrs = builtins.removeAttrs attrs [ "node_modules_attrs" "passthru" "shellHook" "buildInputs" ];
    in
    mkShell ({
      buildInputs = buildInputs ++ [ nm.nodejs nm ];
      shellHook = ''
        # FIXME: we should somehow register a GC root here in case of a symlink?
        ${add_node_modules_to_cwd nm node_modules_mode}
      '' + shellHook;
      passthru = passthru // {
        node_modules = nm;
      };
    } // extraAttrs);

  build =
    { src
    , buildCommands ? [ "npm run build" ]
    , installPhase
    , node_modules_attrs ? { }
    , node_modules_mode ? "symlink"
    , buildInputs ? [ ]
    , passthru ? { }
    , ...
    }@attrs:
    let
      nm = node_modules (get_node_modules_attrs attrs);
      extraAttrs = builtins.removeAttrs attrs [ "node_modules_attrs" "passthru" "buildInputs" ];
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

      passthru = passthru // { node_modules = nm; };
    } // extraAttrs);
}
