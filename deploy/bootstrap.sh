#!/usr/bin/env bash
# Installe et démarre VivriData CI sur une VM Ubuntu.
#  - Appelé automatiquement par cloud-init (Terraform) au premier démarrage de la VM Azure.
#  - Utilisable aussi à la main (plan B sans Terraform) :  sudo bash deploy/bootstrap.sh
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$APP_DIR"

echo "==> 1/5 Fichier d'échange (évite les manques de mémoire sur les petites VM)"
if ! swapon --show | grep -q swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> 2/5 Installation de Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

echo "==> 3/5 Configuration (.env)"
rand() { openssl rand -hex 16; }
if [ ! -f .env ]; then
  cat > .env <<CONF
POSTGRES_DB=vivridata
POSTGRES_USER=vivri
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(rand)}
API_KEY=${API_KEY:-$(rand)}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-$(rand)}
SITE_ADDRESS=${SITE_ADDRESS:-:80}
AZ_STORAGE_ACCOUNT=${AZ_STORAGE_ACCOUNT:-}
APP_VERSION=1.0.0
ENVIRONMENT=${ENVIRONMENT:-production}
CONF
  chmod 600 .env
fi
chown -R "$(stat -c '%U' "$APP_DIR")" .env 2>/dev/null || true

echo "==> 4/5 Construction et démarrage des conteneurs"
bash deploy/update.sh
docker compose --profile tools build backup

echo "==> 5/5 Vérification"
SITE=$(grep ^SITE_ADDRESS= .env | cut -d= -f2)
for i in $(seq 1 36); do
  if [ "$SITE" = ":80" ]; then URL=http://localhost/health; RES=(); else URL="https://$SITE/health"; RES=(--resolve "$SITE:443:127.0.0.1"); fi
  if curl -fsS "${RES[@]}" -o /dev/null "$URL" 2>/dev/null; then echo "Application en ligne : ${URL%/health}"; break; fi
  sleep 5
done
docker compose ps
echo "=== Bootstrap terminé $(date -u) ==="
