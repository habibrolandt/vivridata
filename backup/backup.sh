#!/bin/sh
# Sauvegarde PostgreSQL -> Azure Blob Storage.
# Le jeton d'accès vient de l'identité managée de la VM (service de métadonnées Azure) :
# aucune clé n'est stockée sur le serveur.
set -eu
: "${AZ_STORAGE_ACCOUNT:?AZ_STORAGE_ACCOUNT non défini}"
CONTAINER="${AZ_CONTAINER:-backups}"
BASE="https://${AZ_STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}"
VER="x-ms-version: 2021-08-06"

token() {
  curl -sf -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://storage.azure.com/" \
    | jq -r .access_token
}

case "${1:-backup}" in
  backup)
    FILE="vivridata_$(date -u +%Y%m%d_%H%M%S).sql.gz"
    echo "Export de la base ${PGDATABASE}..."
    pg_dump --no-owner | gzip > "/tmp/${FILE}"
    echo "Envoi vers ${BASE}/backups/${FILE}"
    curl -sf -X PUT -H "Authorization: Bearer $(token)" -H "$VER" -H "x-ms-blob-type: BlockBlob" \
      -H "Content-Type: application/gzip" --data-binary "@/tmp/${FILE}" \
      "${BASE}/backups/${FILE}" > /dev/null
    echo "Sauvegarde terminée ($(du -h "/tmp/${FILE}" | cut -f1))."
    ;;
  list)
    curl -sf -H "Authorization: Bearer $(token)" -H "$VER" \
      "${BASE}?restype=container&comp=list&prefix=backups/" \
      | grep -o '<Name>[^<]*</Name>\|<Content-Length>[^<]*</Content-Length>' \
      | sed 's/<[^>]*>//g' | paste - - | awk '{printf "%s  (%s octets)\n", $1, $2}'
    ;;
  restore)
    FILE="${2:?Usage: restore <nom_du_fichier>}"
    curl -sf -H "Authorization: Bearer $(token)" -H "$VER" "${BASE}/backups/${FILE}" | gunzip | psql --quiet
    echo "Restauration de ${FILE} terminée."
    ;;
  *)
    echo "Usage: backup | list | restore <fichier>"; exit 1 ;;
esac
