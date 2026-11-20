#!/usr/bin/env bash
set -euo pipefail

namespace=${1:-medisur}
read -r -p 'Usuario de GHCR: ' GHCR_USER
read -r -s -p 'Token de GHCR con read:packages: ' GHCR_TOKEN
printf '\n'
if [[ -z "$GHCR_USER" || -z "$GHCR_TOKEN" ]]; then
  echo "Se requiere usuario y token de lectura de GHCR." >&2
  exit 1
fi
export GHCR_USER GHCR_TOKEN

config=$(mktemp)
trap 'rm -f -- "$config"; unset GHCR_TOKEN' EXIT
chmod 600 "$config"
python3 - "$config" <<'PY'
import base64
import json
import os
import sys

auth = base64.b64encode(
    f"{os.environ['GHCR_USER']}:{os.environ['GHCR_TOKEN']}".encode()
).decode()
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump({"auths": {"ghcr.io": {"auth": auth}}}, stream)
PY

kubectl -n "$namespace" create secret generic ghcr-pull \
  --type=kubernetes.io/dockerconfigjson \
  --from-file=.dockerconfigjson="$config" \
  --dry-run=client -o yaml | kubectl apply -f -
