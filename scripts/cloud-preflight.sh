#!/usr/bin/env bash
# Read-only Azure preflight for the two-VM MediSur deployment.
# This script never creates resources or changes subscription settings.
set -euo pipefail

region=${1:-}
if [[ -z "$region" ]]; then
  echo "Uso: bash scripts/cloud-preflight.sh REGION" >&2
  echo "Ejemplo: bash scripts/cloud-preflight.sh westus" >&2
  exit 2
fi

if ! command -v az >/dev/null 2>&1; then
  echo "Falta Azure CLI (az)." >&2
  exit 2
fi

account=$(az account show -o json)
subscription_id=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$account")
subscription_name=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])' <<<"$account")
subscription_state=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("state", "desconocido"))' <<<"$account")

printf 'Suscripción: %s (%s)\nEstado informado por CLI: %s\nRegión solicitada: %s\n' \
  "$subscription_name" "$subscription_id" "$subscription_state" "$region"
echo

allowed_regions=$(az policy assignment list \
  --scope "/subscriptions/$subscription_id" \
  --disable-scope-strict-match \
  --query "[?displayName=='Allowed resource deployment regions'].parameters.listOfAllowedLocations.value[]" \
  -o tsv 2>/dev/null || true)

if [[ -n "$allowed_regions" ]]; then
  printf 'Regiones permitidas por la política:\n%s\n' "$allowed_regions"
  if ! grep -Fxq "$region" <<<"$allowed_regions"; then
    echo "RESULTADO: la política de la suscripción no permite $region." >&2
    exit 3
  fi
else
  echo "No pude leer la política de regiones; el chequeo termina sin recomendar un despliegue." >&2
  exit 4
fi

echo
echo 'Tamaños de referencia visibles en la región (esto no garantiza capacidad disponible):'
az vm list-sizes --location "$region" \
  --query "[?name=='Standard_B4ms' || name=='Standard_B2ms'].{SKU:name,vCPU:numberOfCores,RAM_MB:memoryInMB}" \
  -o table

echo
echo 'Cuotas relevantes (el par de VMs requiere 6 vCPU de la familia B y 6 vCPU regionales adicionales):'
usage=$(az vm list-usage --location "$region" -o json)
python3 -c '
import json, sys
for item in json.load(sys.stdin):
    if item.get("name", {}).get("value") in {"cores", "standardBSFamily"}:
        name = item["name"].get("localizedValue", item["name"]["value"])
        print("{:<34} actual {:>4} / límite {}".format(name, item["currentValue"], item["limit"]))
' <<<"$usage"

echo
echo 'VMs existentes en esta región:'
vms=$(az vm list -d -o json)
REGION="$region" python3 -c '
import json, os, sys
for vm in json.load(sys.stdin):
    if vm.get("location") == os.environ["REGION"]:
        print("{:<24} {:<26} {:<20} {}".format(
            vm.get("name", ""), vm.get("resourceGroup", ""),
            vm.get("hardwareProfile", {}).get("vmSize", ""), vm.get("powerState", "")))
' <<<"$vms"

cat <<'NOTICE'

Antes de desplegar, confirma con Azure que la suscripción permite escrituras y que
la oferta/crédito cubre los recursos. Este chequeo es de solo lectura: no solicita
cuotas, no crea recursos y no confirma capacidad física del centro de datos.
NOTICE
