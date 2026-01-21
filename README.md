# sideBar

A full-stack AI assistant platform featuring real-time streaming chat with Claude, integrated note-taking, website archival, and an extensible agent skills system backed by Supabase and R2.

> **For AI Agents:** See [AGENTS.md](./AGENTS.md) for detailed development instructions.

## Features

- **AI Chat** - Real-time streaming conversations with Claude (Anthropic) with multi-turn tool use
- **Note Taking** - Rich markdown editor with TipTap for organizing thoughts and knowledge
- **Website Archival** - Save and archive web pages for later reference
- **Memory Tool** - Persistent user memories stored in the database
- **User Profiles** - Personalized communication styles and custom prompts
- **Agent Skills** - Extensible system for file operations, web scraping, and document processing
- **Location-Aware** - Context-aware prompts with current location and weather
- **Theme Support** - Dark/light mode toggle
- **Secure Execution** - Sandboxed skill execution with tmpfs isolation and resource limits

## Architecture

sideBar is built as a modern, containerized full-stack application:

- **Frontend**: SvelteKit 5 with TypeScript, Tailwind CSS, and TipTap editor (port 3000)
- **Backend**: FastAPI with AsyncAnthropic for Claude streaming (port 8001)
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
SUPABASE_APP_PSWD=your_app_password_optional

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

# View logs
docker compose logs -f

# Stop services
docker compose down
```

Access the application:
- **Frontend**: http://localhost:3000
- **API**: http://localhost:8001
- **API Docs**: http://localhost:8001/docs

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

## iOS App

- **Project**: `ios/sideBar/sideBar.xcodeproj`
- **Requirements**: Xcode 15+, iOS 17+ simulator
- **Local config**: update `ios/sideBar/Config/SideBar.local.xcconfig`, then set the Debug base configuration to `Config/SideBar.xcconfig`.
- **Docs**: see `docs/IOS_ARCHITECTURE.md` for the SwiftUI architecture overview.

Run tests from CLI:

```bash
xcodebuild -project ios/sideBar/sideBar.xcodeproj -scheme sideBar -destination 'platform=iOS Simulator,name=iPhone 15' test
```

### 3. Rebuild After Changes

```bash
# Rebuild specific service
docker compose up -d --build frontend

# Rebuild all services
docker compose up -d --build
```

## Development

### Install Dev Dependencies

For skill validation and testing:

```bash
# Install uv and dev dependencies
uv sync

# Verify installation - validate a single skill
.venv/bin/skills-ref validate skills/skill-creator

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

Use the included skill-creator skill to scaffold new skills:

```bash
# Create a new skill
python skills/skill-creator/scripts/init_skill.py my-new-skill --path ./skills

# Edit the skill definition
vim skills/my-new-skill/SKILL.md

# Validate the new skill
.venv/bin/skills-ref validate skills/my-new-skill

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

- **[Anthropic Claude](https://docs.anthropic.com)** - Main AI engine for chat and tool use
- **[Supabase](https://supabase.com/docs)** - PostgreSQL database with RLS
- **[Cloudflare R2](https://developers.cloudflare.com/r2)** - Object storage for workspace files
- **[Doppler](https://docs.doppler.com)** - Secrets management
- **[Google Gemini](https://ai.google.dev/docs)** - Conversation title generation
- **[Jina AI](https://jina.ai/reader)** - Web scraping and content extraction

## Resources

**Documentation:**
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
