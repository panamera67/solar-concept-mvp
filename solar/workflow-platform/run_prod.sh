#!/bin/bash
set -euo pipefail

echo "🚀 Initialisation du déploiement Solar Workflow Platform (production)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/infra/docker-compose.prod.yml"

# Choix du fichier d'environnement
ENV_FILE="${1:-$ROOT_DIR/infra/.env.prod}"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ Fichier d'environnement introuvable : $ENV_FILE"
  exit 1
fi

echo "✅ Utilisation du fichier d'environnement : $ENV_FILE"
export $(grep -v '^#' "$ENV_FILE" | xargs)

# Build et démarrage des conteneurs
echo "🏗️  Construction et lancement des services..."
docker compose -f "$COMPOSE_FILE" up -d --build

# Attente que Postgres soit prêt
echo "⏳ Attente de la disponibilité de la base de données..."
until docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U "$DB_USER" -d "$DB_NAME"; do
  echo "En attente de Postgres..."
  sleep 3
done
echo "✅ Postgres est prêt"

# Exécution des migrations
echo "🔄 Exécution des migrations..."
docker compose -f "$COMPOSE_FILE" exec -T backend node scripts/migrate.js

# Vérification des logs backend pour confirmer le démarrage
echo "📖 Suivi des logs backend (CTRL+C pour quitter)..."
docker compose -f "$COMPOSE_FILE" logs -f backend
