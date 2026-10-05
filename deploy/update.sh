#!/usr/bin/env bash
# (Re)déploie la dernière version du code présent sur la VM.
# Utilisé par le bootstrap et par le pipeline CI/CD (Azure Run Command).
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"
SHA="$(git -C "$APP_DIR" -c safe.directory="$APP_DIR" rev-parse --short HEAD 2>/dev/null || echo local)"
export APP_VERSION="1.0-${SHA}"     # visible dans le bandeau de l'application
echo "Déploiement de la version ${APP_VERSION}"
docker compose up -d --build --remove-orphans
docker image prune -f >/dev/null
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
