# Deployment Guide

This project ships as two containers (frontend + API) and relies on external services:
- **Supabase Postgres** for structured data
- **Cloudflare R2** for workspace files and assets

## Runtime Dependencies

- **LibreOffice (soffice)** is required in the API container to convert DOCX/XLSX/PPTX files into PDFs during ingestion.

## Environment Variables

Create a `.env` from `.env.example` and fill in:
- Supabase connection settings (`SUPABASE_*`)
- R2 storage settings (`R2_*`)
- API keys (Anthropic, Google, etc.)
- `BEARER_TOKEN` for API auth
- SSL settings (`DISABLE_SSL_VERIFY` for dev only, `CUSTOM_CA_BUNDLE` for production MITM)

## API Versioning

The backend exposes versioned routes under `/api/v1`. Legacy `/api` routes are still available
for backwards compatibility during migration.

## Docker Compose (Recommended)

```bash
# Build and start services
docker compose up -d --build

# Tail logs
docker compose logs -f

# Stop services
docker compose down
```

Endpoints:
- Frontend: http://localhost:3000
- API: http://localhost:8001

## Database Migrations

Migrations are managed with Alembic in `backend/api/alembic`.

```bash
cd backend/api
alembic upgrade head
```

Ensure your Supabase connection env vars are set before running migrations.

## Maintenance Mode (Optional)

The frontend supports a maintenance/holding page controlled by `MAINTENANCE_MODE=true`.

```bash
MAINTENANCE_MODE=true docker compose up -d --build frontend
```

## Frontend Build Notes

SvelteKit builds via Vite:

```bash
cd frontend
npm install
npm run build
```

The production container serves the built output with `adapter-node`.
