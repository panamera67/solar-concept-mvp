#!/usr/bin/env bash
set -euo pipefail

# run_prod.sh - Déploiement production rapide (docker-compose.prod)
# Usage:
#   chmod +x run_prod.sh
#   ./run_prod.sh path/to/.env.prod
#
# Si aucun fichier .env fourni, on prend solar/workflow-platform/.env.prod

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="${1:-$ROOT_DIR/.env.prod}"
REQUIRED_CMDS=(docker docker-compose jq openssl)

# Services (nommés comme dans docker-compose.prod.yml)
DB_SERVICE_NAME="postgres"
BACKEND_SERVICE_NAME="backend"
FRONTEND_SERVICE_NAME="frontend"
NGINX_SERVICE_NAME="nginx"

# Timeout & retries
PG_READY_MAX_RETRIES=60
HEALTH_MAX_RETRIES=30
SLEEP_BETWEEN=2

function echo_err() { echo >&2 "[$(date --iso-8601=seconds)] $*"; }

# 1. Vérifier outils
echo "🔎 Vérification des prérequis..."
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo_err "Commande requise manquante: $cmd. Installe-la puis relance."
    exit 1
  fi
done
echo "✅ Outils OK (docker, docker-compose, jq, openssl)."

# 2. Vérifier fichier .env
if [ ! -f "$ENV_FILE" ]; then
  echo_err "Fichier d'environnement introuvable: $ENV_FILE"
  exit 1
fi
echo "🔐 Chargement des variables d'environnement depuis $ENV_FILE"
set -o allexport
source "$ENV_FILE"
set +o allexport

# 3. Variables requises (contrôle)
REQUIRED_VARS=(DB_USER DB_PASSWORD DB_NAME DB_HOST STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET FRONTEND_URL API_URL)
MISSING_VARS=()
for v in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!v:-}" ]; then
    MISSING_VARS+=("$v")
  fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo_err "Variables d'environnement manquantes dans $ENV_FILE : ${MISSING_VARS[*]}"
  exit 1
fi
echo "✅ Variables d'environnement essentielles présentes."

# 4. Optionnel : créer Docker secrets (Swarm) - décommenter si use Docker Swarm
# echo "🔒 Création Docker secrets (optionnel, Swarm required)..."
# for s in STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET DB_PASSWORD; do
#   secret_name="solar_${s,,}"
#   echo "$secret_name"
#   if ! docker secret ls --format '{{.Name}}' | grep -q "^${secret_name}$"; then
#     echo "Création secret ${secret_name}..."
#     printf "%s" "${!s}" | docker secret create "${secret_name}" - || true
#   else
#     echo "Secret ${secret_name} déjà présent, skip."
#   fi
# done

# 5. Démarrer compose (production)
echo "🚀 Démarrage du stack production (docker compose -f $COMPOSE_FILE up -d)..."
docker compose -f "$COMPOSE_FILE" up --build -d

# 6. Attendre que Postgres soit prêt
echo "⏳ Attente Postgres (pg_isready) dans le container $DB_SERVICE_NAME..."
pg_ready=false
for i in $(seq 1 $PG_READY_MAX_RETRIES); do
  if docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE_NAME" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
    pg_ready=true
    echo "✅ Postgres est prêt (après $i essais)."
    break
  fi
  echo "  - Attente $i/$PG_READY_MAX_RETRIES..."
  sleep $SLEEP_BETWEEN
done
if [ "$pg_ready" = false ]; then
  echo_err "Postgres non prêt après $PG_READY_MAX_RETRIES essais."
  docker compose -f "$COMPOSE_FILE" logs --tail=50 "$DB_SERVICE_NAME"
  exit 1
fi

# 7. Appliquer migrations (idempotent)
echo "🧱 Application des migrations (via le container backend)..."
# On suppose que backend a script: node scripts/migrate.js
docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE_NAME" /bin/sh -lc "node scripts/migrate.js" || {
  echo_err "Échec des migrations. Logs backend :"
  docker compose -f "$COMPOSE_FILE" logs --tail=80 "$BACKEND_SERVICE_NAME"
  exit 1
}
echo "✅ Migrations appliquées."

# 8. Vérification health endpoints
echo "🔁 Vérification du health endpoint backend..."
backend_health_ok=false
for i in $(seq 1 $HEALTH_MAX_RETRIES); do
  HTTP_CODE=$(docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE_NAME" /bin/sh -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:3000/health || true")
  if [ "$HTTP_CODE" = "200" ]; then
    backend_health_ok=true
    echo "✅ Backend healthy (200)."
    break
  fi
  echo "  - Backend health: $HTTP_CODE (attente $i/$HEALTH_MAX_RETRIES)..."
  sleep $SLEEP_BETWEEN
done
if [ "$backend_health_ok" = false ]; then
  echo_err "Backend health non OK après $HEALTH_MAX_RETRIES essais."
  docker compose -f "$COMPOSE_FILE" logs --tail=80 "$BACKEND_SERVICE_NAME"
  exit 1
fi

# 9. Vérification frontend / nginx health (si exposé)
if docker compose -f "$COMPOSE_FILE" ps --services | grep -q "$FRONTEND_SERVICE_NAME"; then
  echo "🔁 Vérification health frontend..."
  frontend_ok=false
  for i in $(seq 1 $HEALTH_MAX_RETRIES); do
    HTTP_CODE=$(docker compose -f "$COMPOSE_FILE" exec -T "$FRONTEND_SERVICE_NAME" /bin/sh -c "curl -s -o /dev/null -w '%{http_code}' http://localhost/ || true" || true)
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
      echo "✅ Frontend reachable (HTTP $HTTP_CODE)."
      frontend_ok=true
      break
    fi
    echo "  - Frontend health: $HTTP_CODE (attente $i/$HEALTH_MAX_RETRIES)..."
    sleep $SLEEP_BETWEEN
  done
  if [ "$frontend_ok" = false ]; then
    echo_err "Frontend non accessible."
    docker compose -f "$COMPOSE_FILE" logs --tail=50 "$FRONTEND_SERVICE_NAME"
  fi
fi

# 10. Smoke tests (API minimal)
echo "🧪 Smoke test: appel API /projects"
PROJECTS_JSON=$(docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE_NAME" /bin/sh -c "curl -s http://localhost:3000/projects || true")
if echo "$PROJECTS_JSON" | jq -e . >/dev/null 2>&1; then
  COUNT=$(echo "$PROJECTS_JSON" | jq 'length')
  echo "✅ /projects OK - $COUNT projets retournés"
else
  echo_err "/projects a retourné une réponse non-JSON ou erreur."
  docker compose -f "$COMPOSE_FILE" logs --tail=40 "$BACKEND_SERVICE_NAME"
  exit 1
fi

# 11. Optionnel: lancer un workflow de vérification (si API expose endpoint de demo)
if docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE_NAME" /bin/sh -c "curl -s -I http://localhost:3000/api/workflows/start >/dev/null 2>&1"; then
  echo "ℹ️ Endpoint /api/workflows/start détecté. Déclenchement d'un flow de test..."
  DEMO_PAYLOAD='{"type":"health_check","payload":{"demo":true}}'
  START_RES=$(docker compose -f "$COMPOSE_FILE" exec -T "$BACKEND_SERVICE_NAME" /bin/sh -c "curl -s -X POST -H 'Content-Type: application/json' http://localhost:3000/api/workflows/start -d '$DEMO_PAYLOAD'")
  if echo "$START_RES" | jq -e . >/dev/null 2>&1; then
    WF_ID=$(echo "$START_RES" | jq -r '.workflowId // .id // empty')
    echo "✅ Workflow de test démarré (id: $WF_ID)"
  else
    echo "⚠️ Le démarrage du workflow de test a retourné une réponse non-JSON (skip)."
  fi
else
  echo "ℹ️ Pas de endpoint /api/workflows/start détecté, skip demo workflow."
fi

# 12. Afficher logs récents (backend + worker)
echo "📜 Logs récents backend (dernieres 60 lignes):"
docker compose -f "$COMPOSE_FILE" logs --tail=60 "$BACKEND_SERVICE_NAME" || true

if docker compose -f "$COMPOSE_FILE" ps --services | grep -q worker; then
  echo "📜 Logs récents worker (dernieres 60 lignes):"
  docker compose -f "$COMPOSE_FILE" logs --tail=60 worker || true
fi

# 13. Vérification SQL finale (exemples)
echo "🧾 Vérifications DB : quelques rows exemples (projects, donations)"
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT id,name,target_amount,funded_amount,status FROM solar_projects LIMIT 5;"
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT id,amount,status,stripe_session_id,created_at FROM donations ORDER BY created_at DESC LIMIT 5;"

# 14. Rapport final
echo "🏁 Déploiement production terminé."
echo " - Backend: http://<host>:$BACKEND_PORT (ou proxy/nginx)"
echo " - Frontend: http://<host>:$FRONTEND_PORT (ou nginx)"
echo " - Vérifier les fichiers de logs et intégrations externes (Stripe, Sentry...)"
echo ""
echo "🔐 Conseils post-déploiement (manuels) :"
echo " - Stocker secrets dans un vault (1Password/HashiCorp/AWS Secrets Manager)."
echo " - Configurer TLS (nginx / reverse proxy) et HSTS."
echo " - Mettre en place monitoring (Prometheus / Grafana / Sentry)."
echo " - Activer backups réguliers Postgres."
echo ""
echo "✅ run_prod.sh terminé."
