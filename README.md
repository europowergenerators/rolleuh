# Rolleuh

Rebuild your NixOS hosts using nixos configuration options.

## Example

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rolleuh.url = "github:europowergenerators/rolleuh"; # <-- Import rolleuh as dependency
  };

  outputs = { self, nixpkgs, rolleuh }: {
    apps = rolleuh.lib.generateDeployments self; # <-- Convert nixosConfigurations into deployment scripts
    nixosConfigurations = {
      myDatabase = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import ./my-database.nix) # <-- Your own host configuration
          rolleuh.nixosModules.rolleuh # <-- Rolleuh nixos options
          {
            rolleuh = { # <-- The deployment configuration of host myDatabase
              sshString = "database-server";
              useSudo = false;
              buildOn = "local";
              substituteOnTarget = true;
              after = [ ];
              before = [ ];
              # tags = []; # Planned
            };
          }
        ];
      };
      myServer = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import ./my-server.nix)
          rolleuh.nixosModules.rolleuh
          {
            rolleuh = {
              sshString = "deploy@api-server-01.internal.example.com";
              useSudo = false;
              buildOn = "local";
              substituteOnTarget = true;
              after = [ "myDatabase" ];
              before = [ ];
              # tags = []; # Planned
            };
          }
        ];
      };
    };
    # ... other configuration omitted ...
  };
}
```

Now you can deploy hosts myDatabase and myServer. Run the following commands in a shell from your flake directory.

```shell
# Only deploy host myDatabase
nix run .#rolleuh.myDatabase

# Only deploy host myServer
nix run .#rolleuh.myServer

# Deploy all hosts in the right order
nix run .#rolleuh-all
```

## Features

✅ Straightforward deployment configuration  
✅ Deploy many hosts in correct order  
📝 Deploy hosts filtered by tag(s)  
📝 Parallel deployments  
📝 Post deployment tests  
📝 Pre-deployment and post-deployment actions (like filesystem snapshots)  

## Credits and alternatives

- Thank you to [nixinate](https://github.com/MatthewCroughan/nixinate) for the keep it simple (KISS) attitude.
- Thank you to [home-manager](https://github.com/nix-community/home-manager) for the directed asyclic graph (DAG) code.
- Thank you to [nixus](https://github.com/infinisil/nixus) for inspiration.