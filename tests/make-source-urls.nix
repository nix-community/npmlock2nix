{ npmlock2nix, testLib }:
testLib.runTests {
  testUrlForDependency = {
    expr = npmlock2nix.internal.makeSourceAttrs "@test" {
      resolved = "https://example.com/package.tgz";
      integrity = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
    };
    expected = {
      name = "_test";
      url = "https://example.com/package.tgz";
      hash = "sha1-hrGk3k+s4YCsVFqD8VA1I9j+0RU=";
    };
  };
}
