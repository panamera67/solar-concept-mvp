#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-demo}"  # demo ou prod
ENV_FILE="${2:-$ROOT_DIR/infra/.env.${MODE}}"

# Charger les variables d'environnement
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Fichier docker-compose
if [ "$MODE" = "prod" ]; then
  COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"
  echo "🚀 Starting Solar Concept in PRODUCTION mode..."
else
  COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.yml"
  echo "🟢 Starting Solar Concept in DEMO mode..."
fi

# Lancer la stack
docker compose -f "$COMPOSE_FILE" up -d --build

# Attendre Postgres
echo "⏳ Waiting for Postgres..."
until docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME"; do
  sleep 2
done
echo "✅ Postgres ready"

# Attendre Backend
echo "⏳ Waiting for Backend..."
until curl -sf "http://localhost:3000/health" >/dev/null; do
  sleep 2
done
echo "✅ Backend ready"

# Attendre Frontend (si disponible)
if [ "$MODE" = "prod" ]; then
  echo "⏳ Waiting for Frontend..."
  until curl -sf "$FRONTEND_URL" >/dev/null; do
    sleep 2
  done
  echo "✅ Frontend ready"
fi

# Exécuter les migrations backend
echo "🔄 Running migrations..."
docker compose -f "$COMPOSE_FILE" exec -T backend node scripts/migrate.js

# Si demo, déclencher workflow test
if [ "$MODE" = "demo" ]; then
  echo "🧪 Triggering demo workflow..."

  DEMO_PAYLOAD=$(cat <<EOF
{
  "workflow": "test_workflow",
  "input": {
    "user": "demo",
    "amount": 100
  }
}
EOF
)

  docker compose -f "$COMPOSE_FILE" exec -T backend sh -c "
echo '$DEMO_PAYLOAD' | curl -s -X POST -H 'Content-Type: application/json' -d @- http://localhost:3000/workflows/start | jq
"

  echo "📄 Demo workflow logs:"
  docker compose -f "$COMPOSE_FILE" logs backend --tail=50

  echo "📊 Demo DB check:"
  docker compose -f "$COMPOSE_FILE" exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -c \"SELECT * FROM workflow_runs ORDER BY created_at DESC LIMIT 5;\"
fi

# Afficher résumé des métriques
echo "📈 Stack metrics:"
docker compose -f "$COMPOSE_FILE" exec -T backend curl -sf http://localhost:3000/metrics || echo "No metrics endpoint"

echo "🏁 Stack ($MODE) started successfully!"
echo "ℹ️ Logs: docker compose -f $COMPOSE_FILE logs -f"
echo "ℹ️ Stop stack: docker compose -f $COMPOSE_FILE down -v"
