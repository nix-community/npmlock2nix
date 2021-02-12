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


  # Description: Takes a string of the format "github:org/repo#revision" and returns
  # an attribute set { org, repo, rev }
  # Type: String -> Set
  parseGitHubRef = str:
    let
      parts = builtins.split "[:#/]" str;
    in
    assert !(builtins.length parts == 7) ->
      builtins.throw "[npmlock2nix] failed to parse GitHub reference `${str}`. Expected a string of format `github:org/repo#revision`";
    rec {
      inherit parts;
      org = builtins.elemAt parts 2;
      repo = builtins.elemAt parts 4;
      rev = builtins.elemAt parts 6;
    };

  # Description: Takes an attribute set describing a git dependency and returns
  # a .tgz of the repository as store path
  # Type: Set -> Path
  buildTgzFromGitHub = { name, org, repo, rev, ref }:
    let
      src = builtins.fetchGit {
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
  # `github:org/repo#revision` into a git fetcher
  # Type: String -> Set -> Path
  makeGithubSource = name: dependency:
    assert !(dependency ? version) ->
      builtins.throw "Missing `version` attribute missing from `${name}`";
    assert (lib.hasPrefix "github: " dependency.version) -> builtins.throw "invalid prefix for `version` field of `${name}` expected `github:`, got: `${dependency.version}`.";
    let
      v = parseGitHubRef dependency.version;
      f = parseGitHubRef dependency.from;
    in
    assert v.org != f.org -> throw "[npmlock2nix] version and from of `${name}` disagree on the GitHub org to fetch from: `${v.org}` vs `${f.org}`";
    assert v.repo != f.repo -> throw "[npmlock2nix] version and from of `${name}` disagree on the GitHub repo to fetch from: `${v.repo}` vs `${f.repo}`";
    let
      src = buildTgzFromGitHub {
        name = "${name}.tgz";
        ref = v.rev;
        inherit (v) org repo rev;
      };
    in
    (builtins.removeAttrs dependency [ "from" ]) // {
      version = "file://" + (toString src);
    };

  # Description: Turns an npm lockfile dependency into a fetchurl derivation
  # Type: String -> Set -> Derivation
  makeSource = name: dependency:
    assert (builtins.typeOf name != "string") ->
      throw "[npmlock2nix] Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf dependency != "set") ->
      throw "[npmlock2nix] Specification of dependency ${toString name} must be a set";
    if dependency ? resolved && dependency ? integrity then
      dependency // { resolved = "file://" + (toString (fetchurl (makeSourceAttrs name dependency))); }
    else if dependency ? from && dependency ? version then
      makeGithubSource name dependency
    else throw "[npmlock2nix] A valid dependency consists of at least the resolved and integrity field. Missing one or both of them for `${name}`. The object I got looks like this: ${builtins.toJSON dependency}";

  # Description: Parses the lock file as json and returns an attribute set
  # Type: Path -> Set
  readLockfile = file:
    let
      content = builtins.readFile file;
      json = builtins.fromJSON content;
    in
    assert
    builtins.typeOf json != "set" ->
    throw "[npmlock2nix] The NPM lockfile must be a valid JSON object";
    # if a lockfile doesn't declare dependencies ensure that we have an empty
    # set. This makes the consuming code eaiser.
    if json ? dependencies then json else json // { dependencies = { }; };

  # Description: Turns a github string reference into a store path with a tgz of the reference
  # Type: String -> String -> Path
  stringToTgzPath = name: str:
    let
      gitAttrs = parseGitHubRef str;
    in
    buildTgzFromGitHub {
      name = "${name}.tgz";
      ref = gitAttrs.rev;
      inherit (gitAttrs) org repo rev;
    };

  # Description: Patch the `requires` attributes of a dependency spec to refer to paths in the store
  # Type: String -> Set -> Set
  patchRequires = name: requires:
    let
      patchReq = name: version: if lib.hasPrefix "github:" version then stringToTgzPath name version else version;
    in
    lib.mapAttrs patchReq requires;


  # Description: Patches a single lockfile dependency (recursively) by replacing the resolved URL with a store path
  # Type: String -> Set -> Set
  patchDependency = name: spec:
    assert (builtins.typeOf name != "string") ->
      throw "[npmlock2nix] Name of dependency ${toString name} must be a string";
    assert (builtins.typeOf spec != "set") ->
      throw "[npmlock2nix] pec of dependency ${toString name} must be a set";
    let
      isBundled = spec ? bundled && spec.bundled == true;
      hasGitHubRequires = spec: (spec ? requires) && (lib.any (x: lib.hasPrefix "github:" x) (lib.attrValues spec.requires));
      patchSource = lib.optionalAttrs (!isBundled) (makeSource name spec);
      patchRequiresSources = lib.optionalAttrs (hasGitHubRequires spec) { requires = (patchRequires name spec.requires); };
      patchDependenciesSources = lib.optionalAttrs (spec ? dependencies) { dependencies = lib.mapAttrs patchDependency spec.dependencies; };
    in
    # For our purposes we need a dependency with
      # - `resolved` set to a path in the nix store (`patchSource`)
      # - All `requires` entries of this dependency that are set to github URLs set to a path in the nix store (`patchRequiresSources`)
      # - This needs to be done recursively for all `dependencies` in the lockfile (`patchDependenciesSources`)
    (spec // patchSource // patchRequiresSources // patchDependenciesSources);

  # Description: Takes a Path to a lockfile and returns the patched version as attribute set
  # Type: Path -> Set
  patchLockfile = file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") ->
      throw "[npmlock2nix] file ${toString file} must be a path or string";
    let content = readLockfile file; in
    content // {
      dependencies = lib.mapAttrs patchDependency content.dependencies;
    };

  # Description: Rewrite all the `github:` references to store paths
  # Type: Path -> Set
  patchPackagefile = file:
    assert (builtins.typeOf file != "path" && builtins.typeOf file != "string") ->
      throw "[npmlock2nix] file ${toString file} must be a path or string";
    let
      # Read the file but also add empty `devDependencies` and `dependencies`
      # if either are missing
      content = builtins.fromJSON (builtins.readFile file);
      patchDep = (name: version:
        if lib.hasPrefix "github:" version then
          "file://${stringToTgzPath name version}"
        else version);
      dependencies = if (content ? dependencies) then lib.mapAttrs patchDep content.dependencies else { };
      devDependencies = if (content ? devDependencies) then lib.mapAttrs patchDep content.devDependencies else { };
    in
    content // { inherit devDependencies dependencies; };

  # Description: Takes a Path to a package file and returns the patched version as file in the Nix store
  # Type: Path -> Derivation
  patchedPackagefile = file: writeText "package.json"
    (
      builtins.toJSON (patchPackagefile file)
    );

  # Description: Takes a Path to a lockfile and returns the patched version as file in the Nix store
  # Type: Path -> Derivation
  patchedLockfile = file: writeText "packages-lock.json"
    (builtins.toJSON (patchLockfile file));

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
    (
      if mode == "copy" then ''
        if [[ -e node_modules ]]; then
          echo '[npmlock2nix] There is already a `node_modules` directory. Not replacing it.' >&2
          exit 1
        fi
        cp --no-preserve=mode -r ${node_modules}/node_modules node_modules
        chmod -R u+rw node_modules
      '' else if mode == "symlink" then ''
        if [[ -e node_modules ]]; then
          if [[ ! -L node_modules ]]; then
            echo '[npmlock2nix] There is already a `node_modules` directory. Not replacing it.' >&2
            exit 1
          elif [[ $(readlink node_modules) == /nix/store/*/node_modules ]]; then
            if [[ $(readlink node_modules) != "${node_modules}/node_modules" ]]; then
              echo '[npmlock2nix] Updating node_modules symlink' >&2
            fi
          else
            echo '[npmlock2nix] There is already a `node_modules` symlink. Not replacing it.' >&2
            exit 1
          fi
        fi
        ln -snf ${node_modules}/node_modules node_modules
      '' else throw "[npmlock2nix] node_modules_mode must be either `copy` or `symlink`"
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
      assert (builtins.typeOf preInstallLinks != "set") ->
        throw "[npmlock2nix] `preInstallLinks` must be an attributeset of attributesets";
      let
        cleanArgs = builtins.removeAttrs args [ "src" "packageJson" "packageLockJson" "buildInputs" "nativeBuildInputs" "nodejs" "preBuild" "postBuild" "preInstallLinks" ];
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
          ln -sf ${patchedPackagefile packageJson} package.json
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

        passthru = {
          inherit nodejs;
          lockfile = patchedLockfile packageLockJson;
          packagesfile = patchedPackagefile packageJson;
        };
      } // cleanArgs);

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

      passthru.node_modules = nm;
    } // extraAttrs);
}
