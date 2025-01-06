{ lib, pkgs, inputs, ... }:
let
  # Manually instantiate the example flake, containing example nixos host configurations
  instantiated-example-flake = lib.fix (final: {
    inputs = {
      self = final;
      inherit (inputs) nixpkgs;
      rolleuh = inputs.self;
    };
    # ERROR; outPath _must_ be the directory of the flake!
    outPath = ./example;
    outputs = (import ./example/flake.nix).outputs final.inputs;
  });

  # Construct deployments from the example hosts
  deployment-apps = inputs.self.lib.generateDeployments instantiated-example-flake;
  deploy-all-script = toString deployment-apps."${pkgs.system}".rolleuh-all.program;
  # Preprovision the developmentMachine testnode with configuration state so no building happens inside the test runtime
  toplevel-host-configurations = lib.mapAttrsToList (_name: host: host.config.system.build.toplevel) instantiated-example-flake.outputs.nixosConfigurations;

  # Must provision all example flake inputs because the test vm's have no internet access (sandboxed)
  flake-registry-options = { ... }: {
    nix = {
      extraOptions = ''
        experimental-features = nix-command flakes
        flake-registry = ${builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}''}
      '';
      registry.nixpkgs.flake = inputs.nixpkgs;
      registry.rolleuh.flake = inputs.self;
    };
  };

  inherit (import ./ssh-keys.nix pkgs) snakeOilPrivateKey snakeOilPublicKey;
in
{
  name = "example-test";
  nodes = {
    myDatabase = { ... }: {
      imports = [
        ./example/base-config.nix
        flake-registry-options
      ];

      # Full configuration is found in ./example/my-database.nix
      # Below is the bare minimum for remote deployment to work!
      services.openssh.settings.PermitRootLogin = "yes";
      users.users.root.openssh.authorizedKeys.keys = [ snakeOilPublicKey ];
      users.users.root.hashedPasswordFile = lib.mkForce null; # Silence password warning

      virtualisation.writableStore = true;
    };

    myServer = { ... }: {
      imports = [
        ./example/base-config.nix
        flake-registry-options
      ];

      # Full configuration is found in ./example/my-database.nix
      # Below is the bare minimum for remote deployment to work!

      virtualisation.writableStore = true;

      users.users.deploy = {
        extraGroups = [ "wheel" ];
        password = "testing";
        isNormalUser = true;
        openssh.authorizedKeys.keys = [ snakeOilPublicKey ];
      };

      nix.settings.trusted-users = [ "deploy" ];
      security.sudo.extraRules = [{
        users = [ "deploy" ];
        commands = [{
          command = "ALL";
          options = [ "NOPASSWD" ];
        }];
      }];
    };

    developmentMachine = { pkgs, ... }: {
      imports = [
        flake-registry-options
      ];
      virtualisation.additionalPaths = toplevel-host-configurations;

      programs.ssh.extraConfig = ''
        Host database-server
          HostName myDatabase
          User root
          IdentityFile ~/.ssh/private_key
          UserKnownHostsFile=/dev/null
          StrictHostKeyChecking=no
        
        Host api-server-01.internal.example.com
          HostName myServer
          User deploy
          IdentityFile ~/.ssh/private_key
          UserKnownHostsFile=/dev/null
          StrictHostKeyChecking=no
      '';
    };
  };
  testScript = ''
    start_all()
    myDatabase.wait_for_unit("sshd.service")
    myServer.wait_for_unit("sshd.service")
    developmentMachine.wait_for_unit("multi-user.target")

    developmentMachine.succeed("mkdir -p ~/.ssh")
    developmentMachine.succeed("(umask 0077; cat ${snakeOilPrivateKey} > ~/.ssh/private_key)")

    developmentMachine.succeed("exec ${deploy-all-script} >&2")

    myDatabase.wait_for_unit("postgresql.service")

    myServer.wait_for_unit("nginx.service")

    # TODO

  '';
}
