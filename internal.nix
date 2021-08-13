{ nodejs, stdenv, mkShell, lib, fetchurl, writeText, writeTextFile, runCommand, fetchFromGitHub }:
rec {
  default_nodejs = nodejs;

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

  # Description: Returns true if the given input character is allowed within a derviation name.
  # Type: String -> Boolean
  # Source: https://github.com/nixos/nix/blob/706777a4a8b13771221f9b0ef3e984a50562e82b/src/libstore/path.cc#L5-L17
  isValidDrvNameChar = c:
    "0" <= c && c <= "9" ||
    "a" <= c && c <= "z" ||
    "A" <= c && c <= "Z" ||
    c == "+" || c == "-" || c == "." || c == "_" || c == "?" || c == "=";

  # Description: Converts a npm package name to something that is compatible with nix
  # Type: String -> String
  makeValidDrvName = str:
    lib.stringAsChars (c: if isValidDrvNameChar c then c else "?") str;

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
  buildTgzFromGitHub = { name, org, repo, rev, ref, hash ? null }:
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
          builtins.fetchGit {
            url = "https://github.com/${org}/${repo}";
            inherit rev ref;
          };
    in
    runCommand
      name
      { } ''
      set +x
      tar -C ${src} -czf $out ./
    '';

  # Description: Turns a dependency with a from field of the format
  # `github:org/repo#revision` into a git fetcher. The fetcher can
  # receive a hash value by calling 'sourceHashFunc' if a source hash
  # map has been provided. Otherwise the function yields `null`.
  # Type: Fn -> String -> Set -> Path
  makeGithubSource = sourceHashFunc: name: dependency:
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
        name = "${name}.tgz";
        ref = f.rev;
        inherit (v) org repo rev;
        hash = sourceHashFunc { type = "github"; value = v; };
      };
    in
    (builtins.removeAttrs dependency [ "from" ]) // {
      version = "file://" + (toString src);
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

  # Description: Turns an npm lockfile dependency into a fetchurl derivation
  # Type: Fn -> String -> Set -> Derivation
  makeSource = sourceHashFunc: name: dependency:
    assert (builtins.typeOf name != "string") ->
      throw "Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf dependency != "set") ->
      throw "Specification of dependency ${toString name} must be a set";
    if dependency ? resolved && dependency ? integrity then
      dependency // { resolved = "file://" + (toString (fetchurl (makeSourceAttrs name dependency))); }
    else if dependency ? from && dependency ? version then
      makeGithubSource sourceHashFunc name dependency
    else if shouldUseVersionAsUrl dependency then
      makeSource sourceHashFunc name (dependency // { resolved = dependency.version; })
    else throw "A valid dependency consists of at least the resolved and integrity field. Missing one or both of them for `${name}`. The object I got looks like this: ${builtins.toJSON dependency}";

  # Description: Parses the lock file as json and returns an attribute set
  # Type: Path -> Set
  readLockfile = file:
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
  stringToTgzPath = sourceHashFunc: name: str:
    let
      gitAttrs = parseGitHubRef str;
    in
    buildTgzFromGitHub {
      name = "${name}.tgz";
      ref = gitAttrs.rev;
      inherit (gitAttrs) org repo rev;
      hash = sourceHashFunc { type = "github"; value = gitAttrs; };
    };

  # Description: Patch the `requires` attributes of a dependency spec to refer to paths in the store
  # Type: Fn -> String -> Set -> Set
  patchRequires = sourceHashFunc: name: requires:
    let
      patchReq = name: version: if lib.hasPrefix "github:" version then stringToTgzPath sourceHashFunc name version else version;
    in
    lib.mapAttrs patchReq requires;


  # Description: Patches a single lockfile dependency (recursively) by replacing the resolved URL with a store path
  # Type: Fn -> String -> Set -> Set
  patchDependency = sourceHashFunc: name: spec:
    assert (builtins.typeOf name != "string") ->
      throw "Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf spec != "set") ->
      throw "spec of dependency ${toString name} must be a set";
    let
      isBundled = spec ? bundled && spec.bundled == true;
      hasGitHubRequires = spec: (spec ? requires) && (lib.any (x: lib.hasPrefix "github:" x) (lib.attrValues spec.requires));
      patchSource = lib.optionalAttrs (!isBundled) (makeSource sourceHashFunc name spec);
      patchRequiresSources = lib.optionalAttrs (hasGitHubRequires spec) { requires = (patchRequires sourceHashFunc name spec.requires); };
      patchDependenciesSources = lib.optionalAttrs (spec ? dependencies) { dependencies = lib.mapAttrs (patchDependency sourceHashFunc) spec.dependencies; };
    in
    # For our purposes we need a dependency with
      # - `resolved` set to a path in the nix store (`patchSource`)
      # - All `requires` entries of this dependency that are set to github URLs set to a path in the nix store (`patchRequiresSources`)
      # - This needs to be done recursively for all `dependencies` in the lockfile (`patchDependenciesSources`)
    (spec // patchSource // patchRequiresSources // patchDependenciesSources);

  # Description: Takes a Path to a lockfile and returns the patched version as attribute set
  # Type: Fn -> Path -> Set
  patchLockfile = sourceHashFunc: file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") ->
      throw "file ${toString file} must be a path or string";
    let content = readLockfile file; in
    content // {
      dependencies = lib.mapAttrs (patchDependency sourceHashFunc) content.dependencies;
    };

  # Description: Rewrite all the `github:` references to wildcards.
  # Type: Fn -> Path -> Set
  patchPackagefile = sourceHashFunc: file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") ->
      throw "file ${toString file} must be a path or string";
    let
      # Read the file but also add empty `devDependencies` and `dependencies`
      # if either are missing
      content = builtins.fromJSON (builtins.readFile file);
      patchDep = (name: version:
        # If the dependency is of the form github:owner/repo#branch the package-lock.json contains the specific
        # revision that the branch was pointing at at the time of npm install.
        # The package.json itself does not contain enough information to resolve a specific dependency,
        # because it only contains the branch name. Therefore we cannot substitute with a nix store path.
        # If we leave the dependency unchanged, npm will try to resolve it and fail. We therefore substitute with a
        # wildcard dependency, which will make npm look at the lockfile.
        if lib.hasPrefix "github:" version then
          "*"
        else version);
      dependencies = if (content ? dependencies) then lib.mapAttrs patchDep content.dependencies else { };
      devDependencies = if (content ? devDependencies) then lib.mapAttrs patchDep content.devDependencies else { };
    in
    content // { inherit devDependencies dependencies; };

  # Description: Takes a Path to a package file and returns the patched version as file in the Nix store
  # Type: Fn -> Path -> Derivation
  patchedPackagefile = sourceHashFunc: file: writeText "package.json"
    (
      builtins.toJSON (patchPackagefile sourceHashFunc file)
    );

  # Description: Takes a Path to a lockfile and returns the patched version as file in the Nix store
  # Type: Fn -> Path -> Derivation
  patchedLockfile = sourceHashFunc: file: writeText "packages-lock.json"
    (builtins.toJSON (patchLockfile sourceHashFunc file));

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
      lib.attrByPath [ spec.value.org spec.value.repo spec.value.rev ] null githubSourceHashMap
    else
      throw "sourceHashFunc: spec.type '${spec.type}' is not supported. Supported types: 'github'";

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
    , githubSourceHashMap ? { }
    , passthru ? { }
    , ...
    }@args:
      assert (builtins.typeOf preInstallLinks != "set") ->
        throw "`preInstallLinks` must be an attributeset of attributesets";
      let
        cleanArgs = builtins.removeAttrs args [ "src" "packageJson" "packageLockJson" "buildInputs" "nativeBuildInputs" "nodejs" "preBuild" "postBuild" "preInstallLinks" "githubSourceHashMap" ];
        lockfile = readLockfile packageLockJson;

        preinstall_node_modules = writeTextFile {
          name = "prepare";
          destination = "/node_modules/.hooks/prepare";
          text =
            let
              preInstallLinkCommands = lib.concatStringsSep "\n" (
                lib.mapAttrsToList
                  (name: mappings: ''
                    if [ "$npm_package_name" == "${name}" ]; then
                    ${lib.concatStringsSep "\n"
                      (lib.mapAttrsToList
                          (to: from: ''
                              dirname=$(dirname ${to})
                              mkdir -p $dirname
                              ln -s ${from} ${to}
                            '')
                          mappings
                      )}
                    fi
                  '')
                  preInstallLinks
              );
            in
            ''
              #! ${stdenv.shell}

              ${preInstallLinkCommands}

              if grep -I -q -r '/bin/' .; then
                source $TMP/preinstall-env
                patchShebangs .
              fi
            '';
          executable = true;
        };

      in
      stdenv.mkDerivation ({
        inherit (lockfile) version;
        pname = makeValidDrvName lockfile.name;
        inherit buildInputs preBuild postBuild;
        dontUnpack = true;

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
          ln -sf ${patchedLockfile (sourceHashFunc githubSourceHashMap) packageLockJson} package-lock.json
          ln -sf ${patchedPackagefile (sourceHashFunc githubSourceHashMap) packageJson} package.json
        '';

        buildPhase = ''
          runHook preBuild
          mkdir -p node_modules/.hooks
          declare -pf > $TMP/preinstall-env
          ln -s ${preinstall_node_modules}/node_modules/.hooks/prepare node_modules/.hooks/preinstall
          export HOME=.
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

        passthru = passthru // {
          inherit nodejs;
          lockfile = patchedLockfile packageLockJson;
          packagesfile = patchedPackagefile packageJson;
        };
      } // cleanArgs);

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
