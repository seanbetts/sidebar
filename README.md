# sideBar

A cross-platform personal AI workspace for iPhone, iPad, Mac, and web. sideBar combines streaming chat, notes, tasks, saved websites, files, and persistent memories with an extensible skills system, backed by Supabase and Cloudflare R2.

> **For AI Agents:** See [AGENTS.md](./AGENTS.md) for detailed development instructions.

## Features

- **Bring your own AI provider** - Connect Anthropic, OpenAI, or Google with your own API key
- **Context-aware chat** - Real-time streaming conversations that can pull from your notes, tasks, websites, files, memories, and recent activity
- **Notes, tasks, websites, and files** - Built-in personal workspace for writing, planning, saving pages, and working with documents
- **Skills system** - Required, Standard, and Store skills that let sideBar search the web, manage content, and connect to external services
- **Cross-device sync** - Your content syncs across iPhone, iPad, Mac, and web, with offline reading for existing content
- **Widgets and extensions** - Home screen widgets, lock screen widgets, Share extension, and Safari extension support
- **Personalization** - User profile, communication style, working relationship, and persistent memories
- **Transparency and control** - Inline skill status, prompt preview, and per-skill enable/disable controls
- **Secure execution** - Sandboxed skill execution with tmpfs isolation and resource limits

## Architecture

sideBar is built as a modern, containerized full-stack application:

- **Apple app**: SwiftUI app for iPhone, iPad, and Mac, plus widgets and extensions
- **Web app**: SvelteKit 5 with TypeScript, Tailwind CSS, and TipTap editor (port 3000)
- **Backend**: FastAPI with SSE chat streaming and a provider-aware AI gateway for Anthropic, OpenAI, and Google (port 8001)
- **Database**: Supabase Postgres (SQLAlchemy ORM)
- **Object Storage**: Cloudflare R2 for workspace files and assets
- **Containerization**: Docker Compose orchestrating all services
- **API Versioning**: `/api/v1` for stable client integrations (legacy `/api` remains during migration)

> **Deep Dive:** See [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) for design decisions, patterns, and learnings from building sideBar.

## Prerequisites

- **Docker** & **Docker Compose** (required)
- **Node.js 20.19+** (for local frontend development and `npm run lint` with JSDoc rules)
- **Python 3.11+** (for local backend development)
- **uv** (Python package manager - for skill validation)
- **Poppler** (`pdftoppm`) for PDF thumbnails in the ingestion pipeline (macOS: `brew install poppler`)

## Quick Start

### 1. Environment Setup

Create a `.env` file in the project root:

```bash
# Copy the example file
cp .env.example .env
```

Required environment variables:

```bash
# Secrets Management (optional if using Doppler)
DOPPLER_TOKEN=your_doppler_token_here

# Authentication (generate a secure random token)
BEARER_TOKEN=your_secure_bearer_token

# Supabase Database
SUPABASE_PROJECT_ID=your_project_id
SUPABASE_USE_POOLER=true
SUPABASE_POOLER_HOST=aws-1-<region>.pooler.supabase.com
SUPABASE_POOLER_USER=postgres.<project_id>
SUPABASE_DB_NAME=postgres
SUPABASE_DB_PORT=5432
SUPABASE_SSLMODE=require
SUPABASE_POSTGRES_PSWD=your_postgres_password
SUPABASE_APP_PSWD=legacy_fallback_optional

# AI APIs (loaded via Doppler or set directly)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
GOOGLE_API_KEY=...

# Location & Weather
GOOGLE_PLACES_API_KEY=...

# Web Scraping
JINA_API_KEY=...

# Storage (R2)
STORAGE_BACKEND=r2
R2_ENDPOINT=https://<account_id>.r2.cloudflarestorage.com
R2_BUCKET=sidebar
R2_ACCESS_KEY_ID=your_r2_access_key_id
R2_ACCESS_KEY=your_r2_access_key_id
R2_SECRET_ACCESS_KEY=your_r2_secret_access_key

# SSL verification (dev only)
# Disable verification only in local/dev if corporate SSL inspection blocks requests.
DISABLE_SSL_VERIFY=false
# Optional custom CA bundle for production environments with SSL interception.
CUSTOM_CA_BUNDLE=/path/to/ca-bundle.pem
```

### 2. Start the Application

```bash
# Start all services
docker compose up -d

# View logs (API, ingestion worker, frontend)
docker compose logs -f skills-api ingestion-worker frontend

# Stop services
docker compose down
```

Access the application:
- **Frontend**: http://localhost:3000
- **API**: http://localhost:8001
- **API Docs**: http://localhost:8001/docs
- **Product Docs**: http://localhost:3001
- **Design Docs**: http://localhost:3002

## Local Development (Native)

For rapid iteration without Docker (secrets loaded via Doppler):

```bash
# First time setup
cp .env.example .env.local
# Edit .env.local with your credentials
./scripts/health-check.sh
ALLOW_PROD_MIGRATIONS=true ./scripts/migrate.sh upgrade
./dev.sh start
```

See [docs/LOCAL_DEVELOPMENT.md](./docs/LOCAL_DEVELOPMENT.md) for the full guide and safety notes when using production Supabase/R2.

`./dev.sh start` now launches both Mintlify previews:
- product docs at `http://localhost:3001`
- internal design docs at `http://localhost:3002`

## iOS App

- **Project**: `ios/sideBar/sideBar.xcodeproj`
- **Requirements**: Xcode with iOS 26 simulator runtime support
- **Local config**: update `ios/sideBar/Config/SideBar.local.xcconfig`, then set the Debug base configuration to `Config/SideBar.xcconfig`.
- **Docs**: see `docs/IOS_ENGINEERING_HANDBOOK.md` for canonical iOS setup, architecture, and operations guidance (`docs/IOS_ARCHITECTURE.md` is a deprecated compatibility pointer).

Run tests from CLI:

```bash
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBar -destination 'platform=iOS Simulator,name=iPhone 15' test            # fast/default unit lane
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBarUI -destination 'platform=iOS Simulator,name=iPhone 15' test          # UI lane
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBarExtensions -destination 'platform=iOS Simulator,name=iPhone 15' test  # extension lane
```

### 3. Rebuild After Changes

```bash
# Rebuild specific service
docker compose up -d --build frontend

# Rebuild all services
docker compose up -d --build
```

## Development

### Shared Assets

Canonical assets live under `assets/`. Current groups:

- `assets/loading/loading-light-44.gif`
- `assets/loading/loading-dark-44.gif`
- `assets/loading/loading-light-128.gif` (reserved for future 128px+ loading surfaces)
- `assets/loading/loading-dark-128.gif` (reserved for future 128px+ loading surfaces)
- `assets/branding/logo-light.png`
- `assets/branding/logo-dark.png`
- `assets/safari-extension/icon-16.png` (and `32/48/64/96/128/256/512`)
- `assets/safari-extension/toolbar-icon.svg`

Sync them to all runtime targets (web app, iOS app, share extension, Safari extension) with:

```bash
scripts/sync-assets.sh
```

Pre-commit runs this sync automatically.

Note: `ios/sideBar/sideBar/Assets.xcassets/AppLogo.imageset` and
`ios/sideBar/sideBarWidgets/Assets.xcassets/AppLogo.imageset` are intentionally not synced yet.

### Install Dev Dependencies

For skill validation and testing:

```bash
# Install uv and dev dependencies
uv sync

# Verify installation - validate a single skill
.venv/bin/skills-ref validate skills/files

# Validate all skills
./backend/scripts/validate-all.sh
```

### Local Development (Without Docker)

**Backend:**
```bash
cd backend
uv sync
uv run uvicorn api.main:app --reload --port 8001
```

**Frontend:**
```bash
cd frontend
npm install
npm run dev
```

## API Reference

All endpoints require Bearer token authentication (except `/api/health`). For complete API documentation including request/response schemas, see the interactive API docs at [http://localhost:8001/docs](http://localhost:8001/docs) when running locally.

## Creating Skills

Create new skills by adding a folder under `backend/skills/` and authoring `SKILL.md` directly:

```bash
# Create a new skill folder
mkdir -p backend/skills/my-new-skill

# Edit the skill definition
vim backend/skills/my-new-skill/SKILL.md

# Validate the new skill
.venv/bin/skills-ref validate backend/skills/my-new-skill

# Or validate all skills
./backend/scripts/validate-all.sh
```

Skills are automatically discovered and loaded when the API starts. Enable/disable skills via the Settings API.

## Testing

sideBar uses pytest for backend tests and vitest for frontend unit/component tests.

### Backend Tests

```bash
# Start the test DB, reset it, and run the full backend suite
./backend/scripts/run_tests.sh

# Optional cleanup (stops the test DB)
CLEANUP_TEST_DB=1 ./backend/scripts/run_tests.sh
```

#### DB-backed test lanes

Backend tests now default to a local test database:

```bash
./backend/scripts/setup_test_db.sh
cd backend
UV_NATIVE_TLS=1 uv run python scripts/check_test_db_connectivity.py
DATABASE_URL=postgresql://sidebar:sidebar_dev@localhost:5433/sidebar_test UV_NATIVE_TLS=1 uv run pytest -q -rs
```

If you use the Docker test database:

```bash
docker compose -f docker-compose.test.yml up -d postgres-test
./backend/scripts/setup_test_db.sh
cd backend && UV_NATIVE_TLS=1 uv run pytest -q -rs
```

To run the hosted Supabase integration lane (explicit opt-in):

```bash
cd backend
USE_SUPABASE_TEST_DB=1 UV_NATIVE_TLS=1 uv run python scripts/check_test_db_connectivity.py
USE_SUPABASE_TEST_DB=1 UV_NATIVE_TLS=1 uv run pytest -q -rs
```

When `USE_SUPABASE_TEST_DB=1` is set, keep hosted project/user settings in `backend/.env.test`.
You can keep `SUPABASE_POSTGRES_PSWD` as a placeholder there when Doppler is configured (`DOPPLER_TOKEN`); the hosted lane fetches the real DB password at runtime.
`SUPABASE_APP_PSWD` is supported only as a legacy fallback and is not required in `backend/.env.test`.
Preflight validation checks for common misconfiguration and runs `SELECT 1` before pytest.
It also verifies the Alembic baseline so test schemas are never unstamped/drifted.

### Frontend Tests

```bash
cd frontend
npm run test
```

### Test-Driven Development

When adding new features, write tests first:

1. Create test file in `tests/`
2. Write test cases (they should fail)
3. Implement the feature
4. Run tests (they should pass)
5. Run full suite before committing

See [AGENTS.md](./AGENTS.md#testing-tdd-workflow) for detailed TDD workflow.

### What's Tested

- ✅ Critical utility scripts (add_skill_dependencies.py)
- ✅ Validation logic (quick_validate.py)
- ✅ Helper modules (XMLEditor, utilities)
- ✅ Complex domain logic (text extraction, document manipulation)

Backend tests live in `backend/tests/`. Frontend tests live in `frontend/src/tests/`.

## Project Structure

```
sideBar/
├── backend/           # FastAPI application
│   ├── api/          # Routers, services, models, executors
│   ├── skills/       # Agent skills directory
│   └── tests/        # Backend tests
├── frontend/          # SvelteKit application
│   └── src/          # Components, stores, routes
├── docs/              # Documentation
├── scripts/           # Utility scripts
└── docker-compose.yml # Multi-service orchestration
```

## Security

sideBar implements multiple security layers:

- **Workspace Isolation** - Skill file operations run against R2-backed storage
- **Tmpfs Sandboxing** - Skills use ephemeral tmpfs working directories
- **Resource Limits** - Skill execution timeouts (30s), output size limits (10MB), concurrency control (5 max)
- **Sandboxed Execution** - Skills run in isolated subprocesses with minimal environment
- **Audit Logging** - All tool executions logged with parameters and duration
- **Container Security** - Non-root user, dropped capabilities, read-only filesystem
- **Bearer Token Auth** - API authentication for all endpoints
- **RLS Policies** - Supabase row-level security for user-scoped tables

## External Services

- **[Anthropic](https://docs.anthropic.com)** - Supported BYOK AI provider for chat and titles
- **[OpenAI](https://platform.openai.com/docs/overview)** - Supported BYOK AI provider for chat, titles, and transcription-backed skills
- **[Google AI](https://ai.google.dev/docs)** - Supported BYOK AI provider for chat and titles
- **[Supabase](https://supabase.com/docs)** - PostgreSQL database with RLS
- **[Cloudflare R2](https://developers.cloudflare.com/r2)** - Object storage for workspace files
- **[Doppler](https://docs.doppler.com)** - Secrets management
- **[Jina AI](https://jina.ai/reader)** - Web scraping and content extraction

## Resources

**Documentation:**
- [Product Documentation](./docs/product/)
- [Architecture & Design Decisions](./docs/ARCHITECTURE.md)
- [API Migration Guide](./docs/API_MIGRATION_GUIDE.md)
- [Local Development Guide](./docs/LOCAL_DEVELOPMENT.md)
- [Testing Philosophy](./docs/TESTING.md)
- [Contributing Guide](./docs/CONTRIBUTING.md)
- [AI Agent Instructions](./AGENTS.md)

**Frameworks:**
- [FastAPI](https://fastapi.tiangolo.com) • [SvelteKit](https://kit.svelte.dev) • [SQLAlchemy](https://docs.sqlalchemy.org)

**Agent Skills:**
- [Agent Skills Specification](https://agentskills.io/specification)
- [skills-ref Validator](https://github.com/agentskills/agentskills/tree/main/skills-ref)
- [Example Skills](https://github.com/anthropics/skills)

## License

See [LICENSE](./LICENSE) for details.

## Contributing

Contributions are welcome! Please see our contribution guidelines in [AGENTS.md](./AGENTS.md).
