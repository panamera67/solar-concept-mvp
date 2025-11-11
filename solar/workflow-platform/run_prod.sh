#!/bin/bash
set -euo pipefail

echo "🚀 Initialisation du déploiement Solar Workflow Platform (production)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="$ROOT_DIR/.env.prod"

if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Fichier .env.prod manquant. Copiez .env.prod.example et remplissez les valeurs réelles."
  exit 1
fi

echo "✅ Environnement chargé depuis $ENV_FILE"
export $(grep -v '^#' "$ENV_FILE" | xargs)

echo "🔧 Construction et lancement de la stack Docker (mode production)"
docker compose -f "$COMPOSE_FILE" up -d --build

echo "⏳ Attente du démarrage de PostgreSQL..."
until docker compose -f "$COMPOSE_FILE" exec -T db pg_isready -U "$POSTGRES_USER" >/dev/null 2>&1; do
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
