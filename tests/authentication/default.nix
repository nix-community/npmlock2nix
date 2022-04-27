{ nixosTest, lib, path, pkgs, runCommandNoCC, npmlock2nix }:

nixosTest {
  name = "authentication";
  nodes.machine = { lib, ... }: {
    services.nginx = {
      enable = true;
      virtualHosts.localhost = {
        # TODO: Enable
        locations."= /hello.tgz" = {
          alias = runCommandNoCC "hello.tgz" { } ''
            tar -C ${./hello} -czf "$out" .
          '';
          extraConfig = ''
            auth_request /auth;
          '';
        };

        locations."= /auth".extraConfig = ''
          if ( $http_authorization = 'Bearer some-token' ) {
              return 204;
          }
          return 401;
        '';
      };

    };

    # Don't attempt to use binary caches, we don't have internet
    nix.binaryCaches = lib.mkForce [ ];
    nix.extraOptions = ''
      hashed-mirrors =
      connect-timeout = 1
    '';

    environment.etc.test.source = ./src;

    nix.nixPath = [ "nixpkgs=${path}" "npmlock2nix=${builtins.fetchGit ../..}" ];

    virtualisation.diskSize = 2048;
    virtualisation.memorySize = 2048;

    # We need these paths to be available in the vm already since we don't have internet
    virtualisation.additionalPaths = [
      pkgs.nodejs-14_x
      pkgs.nodejs-14_x.src
      pkgs.openssl
      pkgs.jq.dev
      pkgs.stdenv
      pkgs.bashInteractive.dev
      pkgs.stdenv.shellPackage
    ]
    # fetchurl uses an overridden curl
    ++ (pkgs.fetchurl { }).nativeBuildInputs;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("nginx.service")
    machine.wait_for_open_port(80)
    output = machine.succeed(r'nix-shell /etc/test')
    print(output)
  '';
}


