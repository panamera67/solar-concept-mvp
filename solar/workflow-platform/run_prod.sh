#!/bin/bash
set -euo pipefail

echo "🚀 Initialisation du déploiement Solar Workflow Platform (production)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"
DEFAULT_ENV_FILE="$ROOT_DIR/.env.prod"
ALT_ENV_FILE="$ROOT_DIR/infra/.env.prod"

if [ $# -ge 1 ]; then
  ENV_FILE="$1"
else
  if [ -f "$DEFAULT_ENV_FILE" ]; then
    ENV_FILE="$DEFAULT_ENV_FILE"
  elif [ -f "$ALT_ENV_FILE" ]; then
    ENV_FILE="$ALT_ENV_FILE"
  else
    ENV_FILE="$DEFAULT_ENV_FILE"
  fi
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Fichier d'environnement introuvable ($ENV_FILE). Copiez infra/.env.prod.example et remplissez les valeurs réelles."
  exit 1
fi

echo "✅ Environnement chargé depuis $ENV_FILE"
export $(grep -v '^#' "$ENV_FILE" | xargs)

echo "🔧 Construction et lancement de la stack Docker (mode production)"
docker compose -f "$COMPOSE_FILE" up -d --build

echo "⏳ Attente du démarrage de PostgreSQL..."
until docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
  sleep 2
done
echo "✅ PostgreSQL opérationnel"

echo "📜 Application des migrations SQL..."
docker compose -f "$COMPOSE_FILE" exec -T backend npm run migrate

echo "🧩 Vérification du workflow API..."
curl -s -X GET "$BACKEND_URL/api/health" | jq

echo "📊 Journaux récents du backend :"
docker compose -f "$COMPOSE_FILE" logs --tail=20 backend

echo "🏁 Déploiement de production terminé avec succès."
