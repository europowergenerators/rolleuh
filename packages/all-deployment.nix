{ lib, writeShellApplication, rolleuh-data }:
let
  # NOTE; ordered-dag-config has structure { name = str; data = attrSet; }
  inherit (rolleuh-data) ordered-dag-config deployments;

  into-script = { name, ... }: package: "echo 'Invoking deployment for host ==>${name}<=='; ${lib.getExe package}";

  tags = builtins.listToAttrs (builtins.map ({ data, ... }: { name = data.name; value = data.tags; }) ordered-dag-config);
  deployment-scripts = builtins.listToAttrs (builtins.map ({ data, ... }: { name = data.name; value = into-script data deployments.${data.name}; }) ordered-dag-config);
in
writeShellApplication {
  name = "rolleuh-all-deployment";
  runtimeInputs = [ ];
  text = ''
    do_usage() {
      echo "rolleuh-all-deployment [options]"
      echo "    -t, --tags         : Filter hosts by tagname"
      echo "                         (Omitting will deploy all qualified hosts)"
    }

    function array_contains {
      local element
      local match=$1
      shift # All next arguments are haystack elements

      for element in "$@"; do 
        if [[ "$element" == "$match" ]]; then
            return 0 # FOUND
        fi
      done
      return 1 # NOT found
    }

    # WARN; Always iterate through order_of_deployments, which is an array!
    # Arrays guarantee iteration order, associative arrays do not.
    ${lib.strings.toShellVar "order_of_deployments" (builtins.map (x: x.data.name) ordered-dag-config)}

    ${lib.strings.toShellVar "tags_of_deployment" tags}
    ${lib.strings.toShellVar "script_of_deployment" deployment-scripts}

    while [[ $# -gt 0 ]] ; do
      key="$1"; shift 1
      case "$key" in
        -t|--tags) IFS=',' read -r -a TAGS <<< "$1"; shift 1 ;;
        --help) do_usage ; exit 0 ;;
        *) do_usage ; exit 1 ;;
      esac
    done

    if [[ -z "''${TAGS[*]}" ]]; then
      echo "🌍 Deploying all configurations according to declared ordering"
      for deployment in "''${order_of_deployments[@]}"; do
        eval "''${script_of_deployment[''$deployment]}"
      done
      exit 0
    fi

    echo "🌍 Deploying configurations that match provided tags: ''${TAGS[*]}"
    for deployment in "''${order_of_deployments[@]}"; do
      IFS=' ' read -r -a haystack <<< "''${tags_of_deployment[''$deployment]}"

      for tag in "''${TAGS[@]}"; do
        if array_contains "''$tag" "''${haystack[@]}"; then
          eval "''${script_of_deployment[''$deployment]}"
        fi
      done
    done

    echo "✅ DONE"
  '';
}
