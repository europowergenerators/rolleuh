{
  # Cannot explicitly refer to inputs because this triggers downloading from internet
  # inputs = {
  #   nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  #   rolleuh.url = "github:europowergenerators/rolleuh"; # <-- Import rolleuh as dependency
  # };

  outputs = { self, nixpkgs, rolleuh }: {
    apps = rolleuh.lib.generateDeployments self; # <-- Convert nixosConfigurations into deployment scripts
    nixosConfigurations = {
      myDatabase = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import ./my-database.nix) # <-- Your own host configuration
          rolleuh.nixosModules.rolleuh # <-- Rolleuh nixos options
          {
            rolleuh = {
              # <-- The deployment configuration of host myDatabase
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
              useSudo = true;
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
