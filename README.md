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

> **Deep Dive:** See [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md) for design decisions, patterns, and learnings from building sideBar.

## Prerequisites

- **Docker** & **Docker Compose** (required)
- **Node.js 20.19+** (for local frontend development and `npm run lint` with JSDoc rules)
- **Python 3.11+** (for local backend development)
- **uv** (Python package manager - for skill validation)

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

For rapid iteration without Docker:

```bash
# First time setup
cp .env.example .env.local
# Edit .env.local with your credentials
./scripts/health-check.sh
ALLOW_PROD_MIGRATIONS=true ./scripts/migrate.sh upgrade
./dev.sh start
```

See [docs/LOCAL_DEVELOPMENT.md](./docs/LOCAL_DEVELOPMENT.md) for the full guide and safety notes when using production Supabase/R2.

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

### Authentication

All endpoints (except `/api/health`) require Bearer token authentication:

```bash
Authorization: Bearer <your_bearer_token>
```

### Core Endpoints

**Chat**
- `POST /api/chat/stream` - Stream chat with SSE (Server-Sent Events)
- `POST /api/chat/generate-title` - Generate conversation title with Gemini

**Conversations**
- `GET /api/conversations` - List all conversations
- `GET /api/conversations/{id}` - Get conversation by ID
- `POST /api/conversations` - Create new conversation
- `PATCH /api/conversations/{id}` - Update conversation
- `DELETE /api/conversations/{id}` - Delete conversation

**Notes**
- `GET /api/notes` - List all notes
- `GET /api/notes/{id}` - Get note by ID
- `POST /api/notes` - Create new note
- `PATCH /api/notes/{id}` - Update note
- `DELETE /api/notes/{id}` - Delete note

**Websites**
- `GET /api/websites` - List archived websites
- `GET /api/websites/{id}` - Get website by ID
- `POST /api/websites` - Save new website
- `DELETE /api/websites/{id}` - Delete website

**Memories**
- `GET /api/memories` - List stored memories
- `POST /api/memories` - Create memory
- `PATCH /api/memories/{id}` - Update memory
- `DELETE /api/memories/{id}` - Delete memory

**Settings**
- `GET /api/settings` - Fetch current user settings
- `PATCH /api/settings` - Update settings (profile fields, styles, enabled skills)
- `POST /api/settings/profile-image` - Upload avatar (max 2MB)
- `GET /api/settings/profile-image` - Fetch avatar
- `DELETE /api/settings/profile-image` - Remove avatar

**Skills**
- `GET /api/skills` - List available skills (filtered to exposed tools)

**Places & Weather**
- `GET /api/places/autocomplete?query=...` - Location autocomplete
- `GET /api/places/reverse-geocode?lat=...&lon=...` - Reverse geocoding
- `GET /api/weather?lat=...&lon=...` - Current weather data

**Health**
- `GET /api/health` - Health check (no authentication required)

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
├── backend/
│   ├── api/                          # FastAPI application
│   │   ├── main.py                   # Entry point, router mounting
│   │   ├── config.py                 # Settings (Pydantic)
│   │   ├── auth.py                   # Bearer token auth
│   │   ├── prompts.py                # Prompt templates
│   │   ├── routers/                  # API endpoints
│   │   │   ├── chat.py              # Chat streaming (SSE)
│   │   │   ├── conversations.py     # Conversation CRUD
│   │   │   ├── notes.py             # Note management
│   │   │   ├── websites.py          # Website archival
│   │   │   ├── settings.py          # User settings
│   │   │   ├── places.py            # Location services
│   │   │   ├── weather.py           # Weather API
│   │   │   └── skills.py            # Skill catalog
│   │   ├── models/                   # SQLAlchemy ORM
│   │   ├── services/                 # Business logic
│   │   ├── executors/                # Skill execution
│   │   ├── security/                 # Path validation, audit
│   │   └── db/                       # Database session
│   ├── docker/                       # Backend Docker configs
│   │   └── Dockerfile.skills-api
│   ├── skills/                       # Agent skills directory
│   ├── tests/                        # Backend tests
│   └── pyproject.toml                # Python dependencies
├── frontend/
│   ├── src/
│   │   ├── lib/
│   │   │   ├── components/          # Svelte components
│   │   │   ├── stores/              # State management
│   │   │   ├── services/            # API clients
│   │   │   ├── types/               # TypeScript types
│   │   │   └── utils/               # Helper functions
│   │   ├── routes/                  # SvelteKit routes
│   │   └── static/                  # Static assets
│   ├── Dockerfile                   # Frontend container
│   ├── package.json                 # NPM dependencies
│   └── svelte.config.js             # SvelteKit config
├── docker-compose.yml               # Multi-service orchestration
├── scripts/                         # Utility scripts
├── .env.example                     # Environment template
├── README.md                        # This file
└── AGENTS.md                        # AI agent instructions

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

## External Services & APIs

### Configuration & Secrets

- **[Doppler](https://doppler.com)** - Secrets management platform
  - [Documentation](https://docs.doppler.com)
  - [Getting Started](https://docs.doppler.com/docs/getting-started)

### AI & LLM

- **[Anthropic Claude API](https://anthropic.com)** - Main AI engine for chat and tool use
  - [API Documentation](https://docs.anthropic.com)
  - [Model Overview](https://docs.anthropic.com/en/docs/models-overview)
  - [Tool Use Guide](https://docs.anthropic.com/en/docs/build-with-claude/tool-use)

- **[Google Gemini API](https://ai.google.dev)** - Used for conversation title generation
  - [API Documentation](https://ai.google.dev/docs)
  - [Gemini Models](https://ai.google.dev/models/gemini)

- **[OpenAI API](https://openai.com)** - Alternative AI models support
  - [API Documentation](https://platform.openai.com/docs)
  - [API Reference](https://platform.openai.com/docs/api-reference)

### Location & Weather

- **[Google Places API](https://developers.google.com/maps/documentation/places/web-service)** - Location autocomplete and geocoding
  - [Place Autocomplete](https://developers.google.com/maps/documentation/places/web-service/autocomplete)
  - [Geocoding API](https://developers.google.com/maps/documentation/geocoding)

- **[Open-Meteo](https://open-meteo.com)** - Free weather forecast API
  - [API Documentation](https://open-meteo.com/en/docs)
  - [Weather API](https://open-meteo.com/en/docs/weather-api)

### Content & Web

- **[Jina AI](https://jina.ai)** - Web scraping and content extraction
  - [Documentation](https://jina.ai/docs)
  - [Reader API](https://jina.ai/reader)

## Resources

### Learning About Agent Skills

- **[What are Skills?](https://agentskills.io/what-are-skills)** - Core concepts and how skills work
- **[Specification](https://agentskills.io/specification)** - Complete format requirements for SKILL.md files
- **[Integration Guide](https://agentskills.io/integrate-skills)** - How to incorporate skills into agents/tools

### Framework Documentation

- **[FastAPI](https://fastapi.tiangolo.com)** - Modern Python web framework
- **[SvelteKit](https://kit.svelte.dev)** - Web application framework
- **[SQLAlchemy](https://docs.sqlalchemy.org)** - Python SQL toolkit and ORM
- **[Tailwind CSS](https://tailwindcss.com)** - Utility-first CSS framework
- **[TipTap](https://tiptap.dev)** - Headless rich text editor

### Tools & References

- **[skills-ref](https://github.com/agentskills/agentskills/tree/main/skills-ref)** - Reference library for validating skills
- **[Skill Creator](./skills/skill-creator/SKILL.md)** - Included skill for creating new skills
- **[Example Skills](https://github.com/anthropics/skills)** - Anthropic's official skills collection
- **[AGENTS.md](https://agents.md)** - Standard format for AI agent development instructions (see our [AGENTS.md](./AGENTS.md))

### Advanced

- **[Skill Client Integration Spec](https://github.com/anthropics/skills/blob/main/spec/skill-client-integration.md)** - Implementing filesystem-based and tool-based skill clients
- **[Agent Skills Repository](https://github.com/agentskills/agentskills)** - Main project repository
- **[Model Context Protocol](https://modelcontextprotocol.io)** - MCP specification for semantic tool definitions

## License

See [LICENSE](./LICENSE) for details.

## Contributing

Contributions are welcome! Please see our contribution guidelines in [AGENTS.md](./AGENTS.md).
