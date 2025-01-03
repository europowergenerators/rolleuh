{ lib, nix, nixos-rebuild, flock, writeShellApplication, rolleuh-data }:
let
  inherit (lib) optionalString;
  inherit (rolleuh-data) flake name host;

  inherit (host.config.rolleuh) sshString useSudo;
  substituteOnTarget = host.config.rolleuh.substituteOnTarget == true;
in
writeShellApplication {
  name = "rolleuh-${name}";
  runtimeInputs = [ nix nixos-rebuild flock ];
  text = ''
    echo "🚀 Deploying configuration for ${name}"

    echo "🔨 Building system closure locally, then activate it on the remote"
    (set -x; NIX_SSHOPTS="-t" flock --timeout 60 /dev/shm/rolleuh-${name} \
      nixos-rebuild switch --flake "${flake}#${name}" --target-host "${sshString}" ${optionalString useSudo "--use-remote-sudo"} ${optionalString substituteOnTarget "-s"} \
    )

    # TODO
  '';
}
