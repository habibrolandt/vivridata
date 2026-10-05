#!/usr/bin/env bash
# Commandes de la démonstration live. Sur la VM :  cd /opt/vivridata && sudo bash deploy/demo.sh <commande>
cd "$(dirname "$0")/.."
SITE=$(grep ^SITE_ADDRESS= .env | cut -d= -f2)
# Les requêtes de démo passent par Caddy en local (127.0.0.1), comme celles venant d'Internet
if [ "$SITE" = ":80" ]; then BASE="http://localhost"; RES=(); else BASE="https://$SITE"; RES=(--resolve "$SITE:443:127.0.0.1"); fi
c() { curl -sk "${RES[@]}" "$@"; }

case "${1:-}" in
  status)  docker compose ps --format 'table {{.Name}}\t{{.Status}}' ;;
  lb)      echo "Qui répond ? (répartition de charge)"
           for i in $(seq 1 8); do c "$BASE/api/info" | grep -o '"instance":"[^"]*"'; done ;;
  scale)   docker compose up -d --scale app="${2:-4}" --no-recreate && sleep 6 && bash "$0" status ;;
  unscale) docker compose up -d --scale app=2 && bash "$0" status ;;
  load)    N="${2:-3000}"; echo "Envoi de $N requêtes (20 en parallèle)... regarde Grafana"
           seq "$N" | xargs -P 20 -I{} curl -sk "${RES[@]}" -o /dev/null "$BASE/api/stats/evolution?produit_id=7"
           echo "Terminé." ;;
  crash)   C=$(docker compose ps -q app | head -1)
           echo "Arrêt brutal du conteneur $(docker inspect -f '{{.Name}}' "$C")"
           docker kill "$C" >/dev/null
           echo "Le service continue de répondre :"
           for i in $(seq 1 5); do c -o /dev/null -w "  HTTP %{http_code}\n" "$BASE/health"; done
           echo "Redémarrage automatique en cours..."; sleep 8; bash "$0" status ;;
  persist) echo "Arrêt et suppression de TOUS les conteneurs..."; docker compose down
           bash deploy/update.sh && echo "Relancé : rafraîchis la page, les relevés saisis sont toujours là" ;;
  backup)  docker compose run --rm backup backup ;;
  backups) docker compose run --rm backup list ;;
  stats)   docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' ;;
  logs)    docker compose logs -f --tail=20 app ;;
  secrets) grep -E '^(API_KEY|GRAFANA_ADMIN_PASSWORD)=' .env ;;
  *) cat <<USAGE
Usage: sudo bash deploy/demo.sh <commande>
  status            état des conteneurs
  lb                montre quelle instance répond à chaque requête
  scale [n]         passe à n instances de l'API (défaut 4)
  unscale           revient à 2 instances
  load [n]          envoie n requêtes (pic de trafic visible dans Grafana)
  crash             tue une instance et prouve que le service continue
  persist           détruit et recrée tous les conteneurs (les données restent)
  backup | backups  sauvegarde la base vers Azure Blob Storage | liste les sauvegardes
  stats | logs      consommation CPU/RAM | journaux de l'API
  secrets           affiche la clé API et le mot de passe Grafana
USAGE
  ;;
esac
