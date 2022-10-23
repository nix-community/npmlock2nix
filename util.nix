# fetchGitWrapped (identical)
# throw (identical)
# buildTgzFromGitHub (identical)
# nodeSource (identical)
# add_node_modules_to_cwd (identical)
# get_node_modules_attrs (identical)
# sourceHashFunc (identical)
# shell (identical)
# build (identical)
# parseGitHubRef <-> parseGitHubRef (different implementation -- should/could be same?)
{ lib, fetchFromGitHub, runCommand }:
rec {

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
      args: builtins.fetchGit (builtins.removeAttrs args [ "allRefs" ]);

  # Description: Custom throw function that ensures our error messages have a common prefix.
  # Type: String -> Throw
  throw = str: builtins.throw "[npmlock2nix] ${str}";

  # Description: Takes an attribute set describing a git dependency and returns
  # a .tgz of the repository as store path. If the attribute hash contains a
  # hash attribute it will provide the value to `fetchFromGitHub` which will
  # also work in restricted evaluation.
  # Type: Set -> Path
  buildTgzFromGitHub = { name, org, repo, rev, ref, hash ? null, sourceOptions ? { }, pack }:
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
      drv = pack sourceOptions.nodejs name ref src;
    in
    if sourceOptions ? sourceOverrides.${name}
    then sourceOptions.sourceOverrides.${name} sourceInfo drv
    else drv;

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

}
