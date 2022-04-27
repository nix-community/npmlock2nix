{ nixosTest, runCommandNoCC /*npmlock2nix, testLib, symlinkJoin, runCommand, nodejs, lib*/ }:

nixosTest {
  name = "authentication";
  nodes.machine = { ... }: {
    services.nginx = {
      enable = true;
      virtualHosts.localhost = {
        basicAuth.bob = "bobs-secret";
        locations."= /hello.tgz".alias = runCommandNoCC "hello.tgz"
          {
            indexjs = ''
              console.log("This is a private package!")
            '';
            passAsFile = [ "indexjs" ];
          } ''
          tmp=$(mktemp -d)
          mv "$indexjsPath" "$tmp"/index.js
          tar -C "$tmp" -czf "$out" .
        '';
      };
    };

    environment.etc.test.source =

      };

    testScript = ''
      start_all()
      machine.wait_for_unit("nginx.service")
      machine.wait_for_open_port(80)
      machine.succeed("nix-build /etc/test")
      machine.succeed("curl http://bob:bobs-secret@localhost/hello.tgz -O")
      machine.succeed("mkdir hello")
      machine.succeed("tar -C hello -xvf hello.tgz")
    '';
  }


