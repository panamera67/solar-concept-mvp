# Workflow Platform (Next.js + Worker + PostgreSQL)

## Architecture
- Next.js app exposes HTTP APIs to start workflows and inspect status.
- PostgreSQL stores workflow and job state, enabling persistence and retries.
- Dedicated worker polls jobs, executes handlers (`sendEmail`, `callApi`), and manages retries/backoff.

## Quickstart
```bash
cp .env.example .env
docker compose -f infra/docker-compose.yml up --build -d
```

Run migrations (from host with `psql` available or inside postgres container):
```bash
cat migrations/*.sql | docker exec -i $(docker ps -qf "name=workflow-platform_postgres") psql -U postgres -d workflows
```

Start a workflow:
```bash
curl -X POST http://localhost:3000/api/workflows/start \
  -H "Content-Type: application/json" \
  -d '{
    "type": "donation_flow",
    "payload": {"userId": "u1"},
    "tasks": [
      {"name": "sendEmail", "payload": {"to": "a@b.com", "subject": "Hi", "body": "Thanks!"}},
      {"name": "callApi", "payload": {"url": "https://httpbin.org/get"}}
    ]
  }'
```

Check status:
```bash
curl "http://localhost:3000/api/workflows/status?id=<workflowId>"
```

## Production Notes
- Scale worker and web independently.
- Set `WORKER_POLL_INTERVAL_MS` and `WORKER_MAX_RETRIES` per workload needs.
- Extend handlers under `worker/src/handlers` with domain-specific actions.
- Add authentication/rate-limiting for public APIs.
- Consider observability: structured logs (already via `pino`), add metrics/tracing as needed.

