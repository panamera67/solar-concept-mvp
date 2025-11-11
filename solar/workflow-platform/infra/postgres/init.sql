-- Initialisation PostgreSQL pour Solar Workflow Platform (production)
-- Personnalisez ce script avec vos extensions, rôles et seeds nécessaires.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Exemple : créer un rôle en lecture seule (commenter si inutile)
-- CREATE ROLE solar_readonly NOLOGIN;
-- GRANT CONNECT ON DATABASE solar_prod TO solar_readonly;
-- GRANT USAGE ON SCHEMA public TO solar_readonly;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO solar_readonly;
