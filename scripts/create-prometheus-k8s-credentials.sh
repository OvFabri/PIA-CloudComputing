#!/usr/bin/env bash
set -euo pipefail

output_dir=${1:-/tmp/medisur-prometheus-secrets}
namespace=medisur
service_account=prometheus-scraper

ca_data=$(kubectl config view --raw --minify -o 'jsonpath={.clusters[0].cluster.certificate-authority-data}')
if [[ -z "$ca_data" ]]; then
  echo "No se pudo obtener el certificado de la API de Kubernetes." >&2
  exit 1
fi

token=$(kubectl -n "$namespace" create token "$service_account" --duration=720h)
expires_at=$(TOKEN="$token" python3 - <<'PY'
import base64
import datetime
import json
import os

payload = os.environ["TOKEN"].split(".")[1]
payload += "=" * (-len(payload) % 4)
exp = json.loads(base64.urlsafe_b64decode(payload))["exp"]
print(datetime.datetime.fromtimestamp(exp, datetime.timezone.utc).isoformat())
PY
)

umask 077
install -d -m 700 "$output_dir"
printf '%s' "$token" > "$output_dir/k8s-scraper.token"
printf '%s' "$ca_data" | base64 --decode > "$output_dir/k8s-ca.crt"
chmod 600 "$output_dir/k8s-scraper.token" "$output_dir/k8s-ca.crt"
unset token
printf 'Credenciales de solo lectura guardadas en %s. No las subas a Git.\n' "$output_dir"
printf 'El clúster reporta que el token vence en %s UTC.\n' "$expires_at"
