#!/bin/bash
set -euo pipefail

# ================================
# SOLAR WORKFLOW PLATFORM - DEMO
# ================================
# Ce script :
# 1. Lance docker compose (build & up)
# 2. Attend que Postgres soit prêt
# 3. Applique les migrations SQL
# 4. Démarre un workflow de démonstration
# 5. Surveille les logs et affiche les transitions
# ================================

COMPOSE_FILE="solar/workflow-platform/infra/docker-compose.yml"
DB_SERVICE="postgres"
DB_USER="postgres"
DB_NAME="workflows"
WEB_SERVICE="web"
WORKER_SERVICE="worker"
DEMO_FILE="/tmp/demo_workflow.json"

echo "🚀 1. Démarrage du stack Docker..."
docker compose -f "$COMPOSE_FILE" up --build -d

echo "⏳ 2. Attente que Postgres soit prêt..."
until docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  sleep 1
done
echo "✅ Postgres prêt."

echo "🧱 3. Application des migrations SQL..."
for f in solar/workflow-platform/migrations/*.sql; do
  echo "   → Migration $f"
  docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME" -f - < "$f" >/dev/null
done
echo "✅ Schéma initialisé."

echo "🧩 4. Déclenchement d’un workflow de démonstration..."
cat > "$DEMO_FILE" <<'JSON'
{
  "type": "demo_flow",
  "payload": {"demo": true},
  "tasks": [
    {"name": "sendEmail", "payload": {"to": "test@example.com", "subject": "Bienvenue", "body": "Merci d’avoir testé Solar Workflow!"}},
    {"name": "callApi", "payload": {"url": "https://httpbin.org/get"}}
  ]
}
JSON

WF_ID=$(docker compose -f "$COMPOSE_FILE" exec -T "$WEB_SERVICE" curl -s -X POST http://localhost:3000/api/workflows/start \
  -H "Content-Type: application/json" -d @"$DEMO_FILE" | jq -r '.workflowId')

if [[ "$WF_ID" == "null" || -z "$WF_ID" ]]; then
  echo "❌ Erreur : impossible de démarrer le workflow."
  exit 1
fi
echo "✅ Workflow démarré avec ID : $WF_ID"

echo "📊 5. Suivi du statut (attente des transitions)..."
for i in {1..20}; do
  STATUS=$(docker compose -f "$COMPOSE_FILE" exec -T "$WEB_SERVICE" curl -s "http://localhost:3000/api/workflows/status?id=$WF_ID")
  PENDING=$(echo "$STATUS" | jq '[.jobs[] | select(.status != "success" and .status != "failed")] | length')
  echo "⏱️  Tentative $i - Jobs en attente: $PENDING"
  if [[ "$PENDING" -eq 0 ]]; then
    echo "✅ Workflow terminé."
    echo "$STATUS" | jq
    break
  fi
  sleep 3
done

echo "📜 6. Logs Worker (10 dernières lignes):"
docker compose -f "$COMPOSE_FILE" logs --tail=10 "$WORKER_SERVICE"

echo "🧮 7. Vérification SQL (état des jobs):"
docker compose -f "$COMPOSE_FILE" exec -T "$DB_SERVICE" psql -U "$DB_USER" -d "$DB_NAME" -c \
"SELECT id,name,status,attempt,last_error FROM workflow_jobs ORDER BY created_at DESC LIMIT 5;"

echo "🏁 8. Démonstration complète avec succès."
