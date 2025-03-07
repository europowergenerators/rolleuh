{
  description = "Rebuild your NixOS hosts using nixos configuration options.";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager.url = "github:nix-community/home-manager/master"; # Explicit unstable
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # USAGE; See https://github.com/nix-systems/nix-systems?tab=readme-ov-file#consumer-usage
    systems.url = "github:nix-systems/default";
  };

  outputs = { self, nixpkgs, home-manager, systems, ... }@inputs:
    let
      inherit (nixpkgs) lib;
      version = "0.0.1-ALPHA";

      # Same shortcut as eachSystem/forSystems, but using a customized instantiation of nixpkgs.
      #
      # NOTE; Valid nixpkgs-config attributes can be found at pkgs/toplevel/default.nix
      # REF; https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/default.nix
      eachSystemOverrideWith = nixpkgs-config: f: lib.genAttrs (import systems)
        (system: f (import (nixpkgs) (nixpkgs-config // { localSystem = { inherit system; }; })));

      # Re-evaluates nixpkgs with a customised nix command that accepts nix CLI v3
      flake-enabled-nix = { config.nix.settings.experimental-features = [ "nix-command" "flakes" ]; };
    in
    {
      # Include this module in your nixos host configuration.
      nixosModules.rolleuh = { lib, ... }: {
        options.rolleuh = lib.mkOption {
          description = "Configure the deployment procedure for this host.";
          default = null;
          type = lib.types.nullOr (lib.types.submodule {
            options = {
              enable = (lib.mkEnableOption "Rolleuh deployment") // { default = true; };
              sshString = lib.mkOption {
                type = lib.types.str;
                description = "The SSH connection string to reach the deployed host.";
              };
              useSudo = lib.mkOption {
                type = lib.types.bool;
                description = "Use sudo on the target host to activate the new configuration.";
              };
              buildOn = lib.mkOption {
                type = lib.types.enum [ "local" ];
                description = "Which host builds the toplevel configuration during deployment.";
              };
              substituteOnTarget = lib.mkOption {
                type = lib.types.enum [ true false ];
                default = true;
                description = "Wheter to upload packages from the build host (false) or letting the target substitute from its own caches (true).";
              };
              after = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Deploy this host configuration after these other hostnames.";
              };
              before = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Deploy this host configuration before these other hostnames.";
              };
              tags = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Identification strings for this host. Deployments can filter on these values.";
              };
            };
          });
        };
      };

      # Call this function to generate deployment scripts for your nixosConfigurations attribute set.
      lib.generateDeployments = flake: eachSystemOverrideWith flake-enabled-nix (pkgs:
        let
          all-hosts = flake.outputs.nixosConfigurations;
          rolleuh-filter = _name: v: (builtins.hasAttr "rolleuh" v.options) && v.config.rolleuh != null && v.config.rolleuh.enable == true;
          # TODO; Write to stderr if rolleuh options are not set, because now "nix run <>" gives a cryptic error saying the attribute does not exist
          hosts-to-deploy = lib.attrsets.filterAttrs rolleuh-filter all-hosts;
          deployments = self.lib.internal.hostDeployments flake pkgs hosts-to-deploy;

          ordered-dag-config = self.lib.internal.constructDag hosts-to-deploy;
          all-deployment = pkgs.callPackage (import ./packages/all-deployment.nix) { rolleuh-data = { inherit ordered-dag-config deployments; }; };
        in
        {
          rolleuh = lib.mapAttrs (name: binPackage: { type = "app"; program = lib.getExe binPackage; }) deployments;
          rolleuh-all = { type = "app"; program = lib.getExe all-deployment; };
        });

      lib.internal.hostDeployments = flake: pkgs: nixosConfigurations:
        let
          host-deployment-memoized = import ./packages/host-deployment.nix;
          into-deployment = name: host: pkgs.callPackage host-deployment-memoized { rolleuh-data = { inherit flake name host; }; };
          deployments = lib.mapAttrs into-deployment nixosConfigurations;
        in
        deployments;

      lib.internal.constructDag = nixosConfigurations:
        let
          into-dag-value = name: host: {
            inherit (host.config.rolleuh) before after; # Ordering information
            # Attribute set carrying the host related information.
            # These data will be passed into the deployment packages.
            data = {
              inherit (host.config.rolleuh) tags;
            };
          };
          dag-eval-config = lib.evalModules {
            modules = [
              ({ ... }: {
                _file = "rolleuh-dag.config";
                options = {
                  warnings = lib.mkOption {
                    type = lib.types.listOf lib.types.str;
                    default = [ ];
                    internal = true;
                  };

                  hosts = lib.mkOption {
                    type = home-manager.lib.hm.types.dagOf (lib.types.submodule ({ dagName, ... }: {
                      options = {
                        name = lib.mkOption { type = lib.types.str; };
                        runner = lib.mkOption { type = lib.types.path; };
                        tags = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
                      };
                      config.name = "${dagName}";
                    }));
                    default = { };
                  };
                };
                config.hosts = lib.mapAttrs into-dag-value nixosConfigurations;
              })
            ];
            class = "rolleuhDagConfig";
          };
          dag-config = lib.showWarnings dag-eval-config.config.warnings dag-eval-config.config;
        in
        # TODO; Print to stderr if there is no topological sort matching the requirements
        (home-manager.lib.hm.dag.topoSort dag-config.hosts).result;

      # Run tests with;
      # nix flake check --print-build-logs --no-eval-cache
      #
      # Run tests interactively (for debugging) with;
      # nix nix build .#checks.x86_64-linux.<ATTRIBUTE NAME, eg: example-test>.driverInteractive && ./result/bin/nixos-test-driver
      checks = eachSystemOverrideWith flake-enabled-nix
        (pkgs: {
          build_test =
            let
              machine = lib.nixosSystem {
                system = pkgs.system;
                modules = [
                  self.nixosModules.rolleuh
                  ({ config, ... }: {
                    networking.hostName = lib.mkForce "machine";
                    rolleuh = {
                      enable = true;
                      sshString = config.networking.hostName;
                      useSudo = true;
                      buildOn = "local";
                      substituteOnTarget = false;
                      after = [ "before-machine" ];
                      before = [ "after-machine" ];
                      tags = [ "check" "example" ];
                    };
                  })
                ];
              };
              deployments = self.lib.internal.hostDeployments "<NOFLAKE>" pkgs { inherit machine; };
              ordered-dag-config = self.lib.internal.constructDag { inherit machine; };
            in
            pkgs.callPackage (import ./packages/all-deployment.nix) { rolleuh-data = { inherit ordered-dag-config deployments; }; };
        }
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          # nixOS tests can only run on Linux hosts
          example-test = pkgs.testers.runNixOSTest ({ ... }: {
            imports = [ ./checks/example-test.nix ];
            _module.args = { inherit inputs; };
          });
        });
    };
}
