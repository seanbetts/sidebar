---
title: "Architecture & Design Decisions"
description: "Key architectural decisions, design patterns, and learnings for sideBar."
---

# Architecture & Design Decisions

This document captures key architectural decisions, design patterns, and learnings from building sideBar.

## Table of Contents

- [Design Patterns](#design-patterns)
- [Key Architectural Decisions](#key-architectural-decisions)
- [Data Flow](#data-flow)
- [Security Model](#security-model)
- [Performance Considerations](#performance-considerations)
- [Learnings & Trade-offs](#learnings--trade-offs)

---

## Design Patterns

### UI Simplicity vs AI Context Richness

**Key Insight:** What you display in the UI can be minimal and user-friendly, while the AI context can be far more detailed and structured.

This separation of concerns allows for:
- Clean, uncluttered user interfaces
- Rich, contextual AI interactions
- Flexibility to enhance AI capabilities without UI changes

#### Example: Weather Data

**UI Display:**
- Temperature (e.g., "18°C")
- Simple weather icon
- Basic description (e.g., "Partly cloudy")

**AI Context:**
```
Current Weather Snapshot:
- temperature_2m: 18°C
- apparent_temperature: 16°C (feels like)
- weather_code: 3 → "Partly cloudy"
- is_day: true → "daytime"
- wind_speed_10m: 12 km/h
- wind_direction_10m: 245° → "WSW"
- precipitation: 0 mm
- cloud_cover: 45%

3-Day Forecast:
- Today: 18°C / 12°C, partly cloudy, 20% precip
- Tomorrow: 16°C / 10°C, overcast, 60% precip
- Day 3: 15°C / 9°C, light rain, 80% precip
```

This allows the AI to:
- Make weather-aware suggestions ("It might rain tomorrow, perhaps indoor activities?")
- Understand context ("The wind is strong from the west, which explains...")
- Provide detailed recommendations without cluttering the UI

#### Example: Location Data

**UI Display:**
- "London, UK"

**AI Context:**
```
Location Hierarchy:
- City: London
- Borough: Westminster
- Region: Greater London
- Country: United Kingdom
- Coordinates: 51.5074° N, 0.1278° W
- Timezone: Europe/London (UTC+0)
- Administrative Levels:
  - admin_level_4: Greater London
  - admin_level_6: Westminster
```

#### Example: User Profile

**UI Display:**
- Name and avatar
- Basic settings toggles

**AI Context:**
```
User Profile:
- name: Sean
- job_title: Software Engineer
- employer: Tech Co
- location: London, UK
- timezone: Europe/London
- age: 32
- pronouns: he/him

Communication Style:
- Tone: Professional but friendly
- Detail level: Concise with technical depth
- Preferences: Code examples, direct answers

Working Relationship:
- Context: Long-term collaboration
- Trust level: High autonomy
- Expertise areas: Full-stack development, AI integration
```

### Progressive Enhancement Pattern

Features are built with progressive enhancement in mind:
1. **Core Functionality:** Works with minimal data
2. **Enhanced with Context:** Becomes smarter with additional information
3. **Graceful Degradation:** Falls back cleanly when data unavailable

Example: Chat works without location, but becomes location-aware when provided.

---

## Key Architectural Decisions

### 1. JSONB Message Storage

**Decision:** Store conversation messages as JSONB array in PostgreSQL rather than separate messages table.

**Rationale:**
- Single query retrieves entire conversation (no joins)
- Flexible schema for evolving message structure
- GIN indexing enables fast search across message content
- Tool calls naturally nested within messages

**Trade-offs:**
- ✅ Simpler queries, better read performance
- ✅ Atomic conversation updates
- ❌ Harder to query individual messages across conversations
- ❌ Large conversations could hit size limits (mitigated by pagination)

**Implementation:** `backend/api/models/conversation.py:15`

### 2. Server-Sent Events (SSE) for Streaming

**Decision:** Use SSE instead of WebSockets for chat streaming.

**Rationale:**
- Unidirectional communication (server → client) sufficient for streaming tokens
- Simpler protocol than WebSockets
- Better compatibility with proxies and load balancers
- Built-in reconnection in EventSource API
- HTTP-based, easier to secure and monitor

**Trade-offs:**
- ✅ Simpler implementation
- ✅ Better compatibility
- ✅ Automatic reconnection
- ❌ Unidirectional only (acceptable for this use case)

**Implementation:** `backend/api/routers/chat.py:64` (stream endpoint)

### 3. Skill-Based Tool System

**Decision:** Implement tools as discrete Python scripts following Agent Skills specification rather than inline Python functions.

**Rationale:**
- Sandboxing and security isolation
- Reusability across different AI agents
- Clear separation of concerns
- Easier to validate and test
- Community sharing and standardization

**Trade-offs:**
- ✅ Strong security boundaries
- ✅ Reusable, standardized format
- ✅ Easy to validate and share
- ❌ Additional subprocess overhead
- ❌ More complex debugging

**Implementation:** `backend/api/executors/skill_executor.py:20`

### 4. Supabase + R2 for Persistence

**Decision:** Use Supabase Postgres for relational data and Cloudflare R2 for object storage.

**Rationale:**
- Managed Postgres with built-in pooling and RLS
- Object storage for workspace files and assets
- Clear separation between structured data and blobs
- Scales independently of the API layer

**Trade-offs:**
- ✅ Managed infrastructure and backups
- ✅ RLS for user scoping
- ❌ External dependency on Supabase/R2 availability
- ❌ Requires careful credential management

**Implementation:** `backend/api/config.py` (Supabase settings), `backend/api/services/storage/`

### 5. Doppler for Secrets Management

**Decision:** Use Doppler for centralized secrets management rather than .env files.

**Rationale:**
- Centralized secret storage
- Environment-specific configurations
- Audit logging for secret access
- Team collaboration without sharing secrets
- Automatic rotation support

**Trade-offs:**
- ✅ Better security and audit trail
- ✅ Team-friendly secret sharing
- ✅ Environment separation
- ❌ External dependency
- ❌ Requires Doppler token for local dev

**Implementation:** `docker-compose.yml:40` (DOPPLER_TOKEN env var)

### 5. FastAPI + SvelteKit Split

**Decision:** Separate backend (FastAPI) and frontend (SvelteKit) rather than monolithic framework.

**Rationale:**
- Independent scaling of frontend and backend
- Technology flexibility (best tool for each layer)
- Clear API boundaries
- Easier to add mobile clients later
- Better developer experience (hot reload for both)

**Trade-offs:**
- ✅ Flexibility and scalability
- ✅ Clear separation of concerns
- ✅ Better DX with independent hot reload
- ❌ Additional deployment complexity
- ❌ CORS and authentication coordination

### 6. Storage Abstraction + Tmpfs

**Decision:** Route file operations through a storage abstraction (R2) and keep skill scratch space on tmpfs.

**Rationale:**
- Avoid persistent local workspace volumes
- Centralized storage for files across containers
- Ephemeral local data reduces risk and cleanup burden

**Trade-offs:**
- ✅ Consistent storage across environments
- ✅ Reduced local state
- ❌ Network dependency for file access
- ❌ Slightly higher latency for large file operations

**Implementation:** `backend/api/services/storage/`, `docker-compose.yml` tmpfs config

#### Skill Output Metadata
- File-producing skills return `file_id` plus derivative metadata instead of raw storage paths.
- AI context is standardized in `{user_id}/files/{file_id}/ai/ai.md` with backward-compatible frontmatter.

---

## Data Flow

### Chat Message Lifecycle

```
1. User Input (Frontend)
   └─> ChatInput.svelte

2. Message Creation
   └─> chatStore.sendMessage()
       - Generates user_message_id
       - Generates assistant_message_id
       - Creates optimistic UI updates

3. API Request
   └─> POST /api/chat/stream (SSE)
       - Includes message, conversation_id, context

4. Backend Processing
   └─> chat.py:stream_chat()
       - Fetches user settings
       - Builds system prompt with context
       - Retrieves enabled skills
       - Streams to Claude API

5. Claude Response Streaming
   └─> ClaudeClient.stream_with_tools()
       - Streams text tokens via SSE
       - Detects tool use requests
       - Executes skills via SkillExecutor
       - Returns tool results to Claude
       - Continues streaming

6. Frontend Updates
   └─> SSE Event Handlers
       - token: Append to message content
       - tool_call: Show tool execution status
       - tool_result: Update with results
       - complete: Finalize message
       - error: Show error state

7. Persistence
   └─> Conversation saved to PostgreSQL
       - Messages array updated
       - title generated (if new conversation)
       - Metadata updated (message_count, etc.)
```

### Tool Execution Flow

```
1. Claude requests tool use
   └─> Tool call detected in stream

2. Tool Mapping
   └─> ToolMapper.execute_tool()
       - Maps Claude tool name to skill
       - Validates tool enabled
       - Builds arguments

3. Security Validation
   └─> Storage path validation
       - Scopes paths by user ID and category
       - Normalizes paths to prevent traversal
       - Restricts writes to configured storage backend

4. Skill Execution
   └─> SkillExecutor.execute()
       - Validates script path
       - Enforces concurrency limit (semaphore)
       - Sets timeout (30s)
       - Runs subprocess with minimal env

5. Result Processing
   └─> JSON output parsed
       - Success: Return result to Claude
       - Error: Return error message
       - Timeout: Return timeout error

6. Audit Logging
   └─> AuditLogger.log_tool_call()
       - Tool name, parameters, duration
       - Success/failure status
       - User context
```

---

## Security Model

### Defense in Depth

sideBar implements multiple security layers:

#### 1. Container Security
- Non-root user (UID 1000)
- Dropped Linux capabilities (ALL)
- Read-only root filesystem
- No new privileges
- Tmpfs with noexec

**Implementation:** `docker-compose.yml:49-58`

#### 2. Storage Scoping
- File operations routed through R2-backed storage service
- Workspace access scoped by user ID and category
- Path normalization to prevent traversal

#### 3. Resource Limits
- **Execution timeout:** 30 seconds per skill
- **Output size:** 10MB maximum
- **Concurrency:** 5 simultaneous skill executions
- **Memory:** Container limits via Docker

**Implementation:** `backend/api/config.py:31-33`

#### 4. Skill Sandboxing
- Subprocess isolation
- Minimal environment variables
- No inherited file descriptors
- Read-only skill directory mount
- Tmpfs working directory for ephemeral writes

**Implementation:** `backend/api/executors/skill_executor.py:45-70`

#### 5. Authentication
- Bearer token for all API endpoints
- Future: JWT with expiry and refresh tokens

**Implementation:** `backend/api/auth.py`

#### 6. Row-Level Security (RLS)
- Supabase policies enforce per-user access
- Session user ID propagated via `SET app.user_id`

**Implementation:** `backend/api/db/session.py`, Supabase policies

### Security Trade-offs

**Strict but Usable:**
- Path jailing limits flexibility but prevents major security issues
- Write allowlists require explicit configuration but prevent accidents
- Timeouts may interrupt long-running tasks but prevent hangs

**Future Enhancements:**
- JWT with user identity and expiry
- Rate limiting per user
- Skill-level permission system
- Output sanitization for XSS prevention

---

## Performance Considerations

### 1. Denormalization for Reads

**Pattern:** Store computed values alongside source data.

**Examples:**
- `message_count` on conversations (avoid counting JSONB array)
- `first_message` preview (avoid parsing JSONB)
- User settings cached in memory

**Trade-off:** Write complexity for read performance.

### 2. Caching Strategy

#### Weather Cache
- TTL: 30 minutes (1800s)
- Key: Rounded lat/lon (2 decimal places)
- In-memory dictionary
- Reduces API calls for nearby locations

**Implementation:** `backend/api/routers/weather.py:18-40`

#### Database Connection Pooling
- SQLAlchemy connection pool
- Reuses connections across requests
- Configurable pool size

### 3. Streaming vs Buffering

**Decision:** Stream tokens immediately rather than buffering complete responses.

**Benefits:**
- Lower perceived latency
- Better UX (see response forming)
- Handles long responses gracefully

**Implementation:** SSE with `yield` in async generator

### 4. GIN Indexing for JSONB

- Full-text search across conversation messages
- Fast lookups within nested structures
- Enables complex queries without scanning

**Implementation:** `backend/api/models/conversation.py:25`

### 5. Lazy Loading

- Skills loaded on-demand, not at startup
- User settings fetched per-request (with caching)
- Frontend components code-split via SvelteKit

---

## Performance Monitoring

### Frontend Metrics
- **Web Vitals:** Captured in `frontend/src/lib/utils/performance.ts` and sent to `/api/v1/metrics/web-vitals`.
- **Chat Metrics:** Captured in `frontend/src/lib/utils/chatMetrics.ts` and sent to `/api/v1/metrics/chat`.
- **Transport:** Uses `navigator.sendBeacon` with fetch fallback to avoid blocking UX.
- **Env Controls:** Metrics endpoints and sampling are driven by `PUBLIC_*` env vars (see `.env.example`).

### Backend Metrics
- **Prometheus:** `/metrics` exposes HTTP, chat, tool, storage, and DB pool metrics (`backend/api/metrics.py`).
- **Ingestion:** `backend/api/routers/metrics.py` accepts web-vitals and chat metrics from the frontend.

### Error Monitoring
- **Sentry (Frontend):** Initialized in `frontend/src/lib/config/sentry.ts` and `frontend/src/hooks.client.ts`.
- **Sentry (Backend):** Configured in `backend/api/main.py` via `SENTRY_*` settings.

---

## Learnings & Trade-offs

### What Worked Well

#### 1. JSONB for Message Storage
Initially skeptical, but the simplicity of single-query conversation retrieval outweighed the downsides. GIN indexing makes search fast enough.

#### 2. Agent Skills Specification
Standardized format made it easy to add new capabilities. Community patterns emerging.

#### 3. SSE for Streaming
Much simpler than WebSockets for unidirectional streaming. Reconnection handled automatically by browser.

#### 4. Doppler Integration
Eliminated .env file sharing in team. Environment separation became trivial.

#### 5. Storage Scoping
Sleep well knowing skills cannot escape their scoped storage prefixes. Zero security incidents.

### What We'd Do Differently

#### 1. Earlier Investment in Testing
Added tests later rather than from the start. TDD would have caught integration issues earlier.

#### 2. Schema Migrations from Day One
Used Alembic from the start. Hand-crafted SQL migrations became painful.

#### 3. Structured Logging Earlier
Added structured logging later. Would have helped debugging production issues.

#### 4. API Versioning
No versioning initially. Breaking changes harder to manage. We later added `/api/v1/` paths with deprecation middleware for legacy `/api/*` routes (sunset: 2026-06-01).

### Interesting Challenges

#### 1. Corporate SSL Interception
Company MITM proxy broke httpx SSL verification. Created custom client with configurable SSL verification.

**Solution:** `JINA_SSL_VERIFY=false` option in config

#### 2. Multi-turn Tool Use Loops
Claude sometimes requests multiple tools sequentially. Had to implement loop with max iterations to prevent infinite loops.

**Solution:** Max 5 tool use rounds per message

#### 3. Message ID Deduplication
Duplicate messages on reconnect. Frontend generates IDs to prevent duplicates on backend.

**Solution:** `user_message_id` in request payload

#### 4. Skill Output Size
Some skills (PDF extraction) returned massive outputs, breaking responses.

**Solution:** 10MB output limit with truncation

### Future Architectural Considerations

#### 1. Multi-User Support
Currently single-user with extensible `user_id` field. Full multi-user requires:
- JWT authentication with user identity
- User-scoped data isolation
- Per-user rate limiting
- Billing and quotas

#### 2. Skill Marketplace
Community skill sharing requires:
- Skill signing and verification
- Dependency management
- Version compatibility
- Security reviews

#### 3. Horizontal Scaling
Current architecture allows horizontal scaling of:
- ✅ Frontend (stateless SvelteKit)
- ✅ Backend API (FastAPI stateless with external DB)
- ⚠️ Skill execution (needs distributed locking for concurrency limits)

Would require:
- Redis for distributed caching and locking
- Shared storage for files (R2 already supports this)
- Database connection pooling

#### 4. Real-time Collaboration
Multiple users editing same note requires:
- WebSocket bidirectional communication
- Operational transforms or CRDTs
- Conflict resolution
- Presence indicators

---

## References

- **Agent Skills Spec:** https://agentskills.io/specification
- **FastAPI Docs:** https://fastapi.tiangolo.com
- **SvelteKit Docs:** https://kit.svelte.dev
- **PostgreSQL JSONB:** https://www.postgresql.org/docs/current/datatype-json.html
- **Server-Sent Events:** https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events

---

**Last Updated:** 2026-01-04

**Document Owner:** Architecture Team

**Review Cycle:** Quarterly or on major architectural changes
