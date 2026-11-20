#!/usr/bin/env bash
set -euo pipefail

output=${1:-/tmp/medisur-jenkins-kubeconfig}
namespace=medisur
service_account=jenkins-deployer

node_ip=$(kubectl get nodes -o 'jsonpath={.items[0].status.addresses[?(@.type=="InternalIP")].address}')
ca_data=$(kubectl config view --raw --minify -o 'jsonpath={.clusters[0].cluster.certificate-authority-data}')
if [[ -z "$node_ip" || -z "$ca_data" ]]; then
  echo "No se pudo obtener la IP privada del nodo o el certificado de la API." >&2
  exit 1
fi

token=$(kubectl -n "$namespace" create token "$service_account" --duration=720h)
if [[ -z "$token" ]]; then
  echo "No se pudo crear el token del service account." >&2
  exit 1
fi
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
cat > "$output" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: medisur
    cluster:
      certificate-authority-data: ${ca_data}
      server: https://${node_ip}:16443
contexts:
  - name: jenkins-deployer@medisur
    context:
      cluster: medisur
      namespace: medisur
      user: jenkins-deployer
current-context: jenkins-deployer@medisur
users:
  - name: jenkins-deployer
    user:
      token: ${token}
EOF
chmod 600 "$output"
unset token
printf 'Kubeconfig creado en %s con permisos 600. No lo agregues al repositorio.\n' "$output"
printf 'El clúster reporta que el token vence en %s UTC.\n' "$expires_at"
