{ lib, writeShellApplication, rolleuh-data }:
let
  inherit (rolleuh-data) sorted-dag-config;

  into-script = _: data: ''
    echo "Deploying ${data.name}"
    ${data.runner}
  '';
in
writeShellApplication {
  name = "rolleeuh-all-deployment";
  runtimeInputs = [ ];
  text = ''
    echo "🌍 Deploying all configurations according to declared ordering"
    
    ${lib.concatStringsSep "\n" (builtins.map (x: into-script x.name x.data) sorted-dag-config)}
  '';
}
