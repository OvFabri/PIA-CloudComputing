#!/usr/bin/env bash
set -euo pipefail

# Pide un PAT de GHCR sin mostrarlo ni guardarlo en el repositorio.
# El PAT se usa solo para que Kubernetes descargue la imagen privada.
node=${K8S_SSH_TARGET:-}
if [[ -z "$node" ]]; then
  echo 'Define K8S_SSH_TARGET, por ejemplo azureuser@IP_PUBLICA_DE_VM_K8S.' >&2
  exit 2
fi
namespace=medisur
secret=ghcr-pull
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
chmod 700 "$tmp"

scp -r kubernetes "$node:/tmp/medisur-kubernetes"
scp kubernetes/jenkins-rbac.yaml "$node:/tmp/jenkins-rbac.yaml"

read -r -p 'Usuario de GitHub con acceso al paquete GHCR: ' gh_user
if [[ -z "$gh_user" ]]; then
  echo 'El usuario de GitHub no puede estar vacío.' >&2
  exit 2
fi
read -r -s -p 'PAT clásico (permisos read:packages): ' gh_token
printf '\n'
if [[ -z "$gh_token" ]]; then
  echo 'El token no puede estar vacío.' >&2
  exit 2
fi

auth=$(printf '%s:%s' "$gh_user" "$gh_token" | base64 -w0)
unset gh_token
printf '{"auths":{"ghcr.io":{"auth":"%s"}}}\n' "$auth" > "$tmp/config.json"
unset auth
chmod 600 "$tmp/config.json"

remote_file="/tmp/ghcr-config-$$.json"
scp "$tmp/config.json" "$node:$remote_file"
ssh "$node" "microk8s kubectl -n '$namespace' create secret generic '$secret' \\
  --from-file=.dockerconfigjson='$remote_file' \\
  --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | \\
  microk8s kubectl apply -f -; rm -f '$remote_file'"

ssh "$node" 'microk8s kubectl apply -k /tmp/medisur-kubernetes && microk8s kubectl apply -f /tmp/jenkins-rbac.yaml && microk8s kubectl -n medisur rollout status deployment/medisur-api --timeout=240s && microk8s kubectl -n medisur get deployment,pods,service,ingress -o wide'
