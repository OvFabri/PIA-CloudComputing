#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -f .env ]]; then
  echo "Copia monitoring/.env.example a monitoring/.env y completa los datos SMTP." >&2
  exit 1
fi
if ! command -v envsubst >/dev/null 2>&1; then
  echo "Instala envsubst con: sudo apt-get install gettext-base" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${ALERT_EMAIL:?Configura ALERT_EMAIL en monitoring/.env}"
: "${SMTP_HOST:?Configura SMTP_HOST en monitoring/.env}"
: "${SMTP_FROM:?Configura SMTP_FROM en monitoring/.env}"
: "${SMTP_USER:?Configura SMTP_USER en monitoring/.env}"

install -d -m 700 alertmanager/secrets
read -r -s -p "Contraseña SMTP o contraseña de aplicación: " smtp_password
printf '\n'
if [[ -z "$smtp_password" ]]; then
  echo "La contraseña no puede estar vacía." >&2
  exit 1
fi
umask 077
printf '%s' "$smtp_password" > alertmanager/secrets/smtp_password
unset smtp_password

envsubst '${ALERT_EMAIL} ${SMTP_HOST} ${SMTP_FROM} ${SMTP_USER}' \
  < alertmanager/alertmanager.yml.tmpl \
  > alertmanager/alertmanager.yml
chmod 600 alertmanager/alertmanager.yml alertmanager/secrets/smtp_password
echo "Configuración privada generada. Ya puedes iniciar docker compose."
