#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="${1:-$ROOT_DIR/infra/.env.prod}"

echo "🌞 Lancement de la stack production avec Docker Compose"
echo "📄 Fichier env utilisé: $ENV_FILE"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Fichier d'environnement introuvable : $ENV_FILE"
  exit 1
fi

# Export des variables d'environnement
set -a
source "$ENV_FILE"
set +a

docker compose -f "$COMPOSE_FILE" up -d --build

wait_for_service() {
  local name=$1
  local cmd=$2
  local retries=20
  local count=0

  echo "⏳ Vérification de la disponibilité de $name..."
  until eval "$cmd"; do
    count=$((count + 1))
    if [ $count -ge $retries ]; then
      echo "❌ $name non disponible après $retries tentatives."
      exit 1
    fi
    sleep 5
  done
  echo "✅ $name est prêt."
}

# Postgres
wait_for_service "Postgres" \
"docker compose -f '$COMPOSE_FILE' exec -T postgres pg_isready -U '$DB_USER' -d '$DB_NAME' >/dev/null 2>&1"

# Migrations
echo "🚀 Exécution des migrations backend..."
docker compose -f "$COMPOSE_FILE" exec -T backend node scripts/migrate.js

# Backend health
wait_for_service "Backend" \
"curl -fsS http://localhost:3000/health >/dev/null 2>&1"

# Frontend health
wait_for_service "Frontend" \
"curl -fsS http://localhost:80 >/dev/null 2>&1"

# Suivi des logs backend/frontend
docker compose -f "$COMPOSE_FILE" logs -f backend frontend &
LOGS_PID=$!

# Fonction de récupération et formatage des métriques
fetch_metrics() {
  local metrics_json
  metrics_json=$(curl -fsS http://localhost:3000/metrics || echo '{}')

  if command -v jq >/dev/null 2>&1; then
    local donations_count
    local total_donated
    local requests
    local uptime

    donations_count=$(echo "$metrics_json" | jq -r '.donations.count // 0')
    total_donated=$(echo "$metrics_json" | jq -r '.donations.total_amount // 0')
    requests=$(echo "$metrics_json" | jq -r '.requests // 0')
    uptime=$(echo "$metrics_json" | jq -r '.uptime // 0')

    echo "================= SOLAR CONCEPT - METRICS ================="
    if [ "$donations_count" -ge 50 ]; then
      echo -e "💰 Donations count: \e[31m$donations_count\e[0m (HIGH)"
    else
      echo -e "💰 Donations count: \e[32m$donations_count\e[0m"
    fi

    if [ "$total_donated" -ge 5000 ]; then
      echo -e "💶 Total donated: \e[31m€$total_donated\e[0m (HIGH)"
    else
      echo -e "💶 Total donated: \e[32m€$total_donated\e[0m"
    fi

    echo "📡 HTTP requests: $requests"
    echo "⏱ Uptime: ${uptime}s"

    local bar_width=40
    local bar_filled=$(( donations_count * bar_width / 100 ))
    local bar_empty=$(( bar_width - bar_filled ))
    printf "📊 Donations visual: |"
    printf "%0.s#" $(seq 1 $bar_filled)
    printf "%0.s-" $(seq 1 $bar_empty)
    printf "|\n"
    echo "=========================================================="
  else
    echo "⚠️ jq non trouvé, affichage brut des métriques:"
    echo "$metrics_json"
  fi
}

trap "echo '🔹 Arrêt du suivi des logs...'; kill $LOGS_PID 2>/dev/null; exit 0" SIGINT

while true; do
  clear
  fetch_metrics
  sleep 15
done
