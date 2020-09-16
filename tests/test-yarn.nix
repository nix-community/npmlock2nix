{ npmlock2nix, testLib, writeText }:
(testLib.runTests {
  testSplitsIntoBlocks = {
    expr = let blocks = npmlock2nix.internal.yarn.splitBlocks ''
      "@babel/code-frame@^7.8.3":
        version "7.8.3"
        resolved "https://registry.yarnpkg.com/@babel/code-frame/-/code-frame-7.8.3.tgz#33e25903d7481181534e12ec0a25f16b6fcf419e"
        integrity sha512-a9gxpmdXtZEInkCSHUJDLHZVBgb1QS0jhss4cPP93EW7s+uC5bikET2twEF3KV+7rDblJcmNvTR7VJejqd2C2g==
        dependencies:
          "@babel/highlight" "^7.8.3"

      "@babel/compat-data@^7.8.4":
        version "7.8.5"
        resolved "https://registry.yarnpkg.com/@babel/compat-data/-/compat-data-7.8.5.tgz#d28ce872778c23551cbb9432fc68d28495b613b9"
        integrity sha512-jWYUqQX/ObOhG1UiEkbH5SANsE/8oKXiQWjj7p7xgj9Zmnt//aUvyz4dBkK0HNsS8/cbyC5NmmH87VekW+mXFg==
        dependencies:
          browserslist "^4.8.5"
          invariant "^2.2.4"
          semver "^5.5.0"''; in
      {
        count = builtins.length blocks;
        inherit blocks;
      };
    expected = {
      count = 2;
      blocks = [
        ''"@babel/code-frame@^7.8.3":
  version "7.8.3"
  resolved "https://registry.yarnpkg.com/@babel/code-frame/-/code-frame-7.8.3.tgz#33e25903d7481181534e12ec0a25f16b6fcf419e"
  integrity sha512-a9gxpmdXtZEInkCSHUJDLHZVBgb1QS0jhss4cPP93EW7s+uC5bikET2twEF3KV+7rDblJcmNvTR7VJejqd2C2g==
  dependencies:
    "@babel/highlight" "^7.8.3"''

        ''"@babel/compat-data@^7.8.4":
  version "7.8.5"
  resolved "https://registry.yarnpkg.com/@babel/compat-data/-/compat-data-7.8.5.tgz#d28ce872778c23551cbb9432fc68d28495b613b9"
  integrity sha512-jWYUqQX/ObOhG1UiEkbH5SANsE/8oKXiQWjj7p7xgj9Zmnt//aUvyz4dBkK0HNsS8/cbyC5NmmH87VekW+mXFg==
  dependencies:
    browserslist "^4.8.5"
    invariant "^2.2.4"
    semver "^5.5.0"''
      ];
    };
  };

  testUnquote = {
    expr = map npmlock2nix.internal.yarn.unquote [ "" "\"" "\"\"" "\"foo\"" "\"foo\":" ];
    expected = [ "" "" "" "foo" "foo\":" ];
  };

  testParseBlock = {
    expr =
      let
        block = ''"@babel/code-frame@^7.8.3":
  version "7.8.3"
  resolved "https://somewhere"
  integrity sha512-bla==
  dependencies:
    "@babel/highlight" "^7.8.3"
  '';
      in
      npmlock2nix.internal.yarn.parseBlock block;

    expected = {
      name = "@babel/code-frame@^7.8.3";
      version = "7.8.3";
      resolved = "https://somewhere";
      integrity = "sha512-bla==";
      dependencies."@babel/highlight" = "^7.8.3";
    };
  };

  testParseFile = {
    expr = let
      res = (npmlock2nix.internal.yarn.parseFile ./concourse-yarn.lock);
    in {
      type = builtins.typeOf res;
      len = builtins.length res;
    };
    expected = {
      type = "list";
      len = 705;
    };
  };

  testToNpmLock = {
    expr = (npmlock2nix.internal.yarn.toNpmLock [
      {
        name = "some-name@^1";
        version = "1";
        resolved = "https://somewhere";
        integrity = "violated";
      }
    ]).dependencies;
    expected = {
      "some-name@^1" = {
        version = "1";
        resolved = "https://somewhere";
        integrity = "violated";
      };
    };
  };

  testToNpmLock = {
    expr = (npmlock2nix.internal.yarn.toNpmLock [
      {
        name = "some-name@^1";
        version = "1";
        resolved = "https://somewhere";
        integrity = "violated";
      }
    ]).dependencies;
    expected = {
      "some-name@^1" = {
        version = "1";
        resolved = "https://somewhere";
        integrity = "violated";
      };
    };
  };

  # testPackageAsNpmLock= {
  #   expr = let
  #     file = writeText "package-lock.json" (builtins.toJSON (npmlock2nix.internal.yarn.toNpmLock (npmlock2nix.internal.yarn.parseFile ./concourse-yarn.lock)));
  #   in npmlock2nix.internal.patchedLockfile (toString file);
  #   expected = {};
  # };

})
