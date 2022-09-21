{ npmlock2nix, testLib }:
testLib.runTests {
  # shouldPatchDepEntryx = {
  #   expr = (i.patchV2Package noSourceOptions "node_modules/yallist" {
  #     version = "4.0.0";
  #     resolved = "https://registry.npmjs.org/yallist/-/yallist-4.0.0.tgz";
  #     integrity = "sha512-3wdGidZyq5PB084XLES5TpOSRA3wjXAlIWMhum2kRcv/41Sn2emQ0dycQW4uZXLejwKvg6EsvbdlVL+FYEct7A==";
  #   });
  #   expected = {
  #     version = "4.0.0";
  #     resolved = "file:///nix/store/4aznbgn0ysywd3yxbhnan1x9mzn4lvq0-yallist-4.0.0.tgz";
  #     integrity = "sha512-3wdGidZyq5PB084XLES5TpOSRA3wjXAlIWMhum2kRcv/41Sn2emQ0dycQW4uZXLejwKvg6EsvbdlVL+FYEct7A==";
  #   };
  # };
  shouldPatchDepEntryx2 = {
    expr = builtins.trace "hello????" true;
    expected = false;
  };
}
