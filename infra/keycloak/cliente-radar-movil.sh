#!/usr/bin/env bash
# Da de alta la app móvil como cliente público (código + PKCE) en el realm `radar` del Keycloak del radar.
# Los tokens llevan la audiencia `radar-api`, así que sirven tanto para la API del radar como para este servidor.
#
# Uso: ./infra/keycloak/cliente-radar-movil.sh [contenedor de Keycloak]   (por defecto, el del compose e2e del radar)
# Es idempotente: si el cliente ya existe, no hace nada.
set -euo pipefail

contenedor="${1:-radar-e2e-keycloak-1}"
kcadm=(docker exec -i "$contenedor" /opt/keycloak/bin/kcadm.sh)

"${kcadm[@]}" config credentials --server http://localhost:8080/auth --realm master \
  --user "${KC_ADMIN:-admin}" --password "${KC_ADMIN_CLAVE:-admin}" >/dev/null

if "${kcadm[@]}" get clients -r radar -q clientId=radar-movil --fields clientId | grep -q radar-movil; then
  echo "El cliente radar-movil ya existe."
  exit 0
fi

"${kcadm[@]}" create clients -r radar -f - < "$(dirname "$0")/cliente-radar-movil.json"
echo "Cliente radar-movil creado."
