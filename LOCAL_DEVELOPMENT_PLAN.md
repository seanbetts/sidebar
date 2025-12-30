# Local Development Workflow - Implementation Plan

## Overview
Set up native (non-Docker) local development with instant hot reload for both backend and frontend, connecting to production Supabase database and R2 storage.

## User Preferences
- **Database**: Supabase production instance
- **Storage**: R2 production bucket
- **Runtime**: Native execution (no Docker rebuilds)
- **Tooling**: Shell scripts (dev.sh, etc.)
- **Workflow**: Develop on `dev` branch → merge to `main` for production

## Critical Files to Create/Modify

### New Files to Create
1. `/Users/sean/Coding/sideBar/.env.local` - Local environment overrides
2. `/Users/sean/Coding/sideBar/dev.sh` - Main startup script
3. `/Users/sean/Coding/sideBar/scripts/health-check.sh` - Setup validation
4. `/Users/sean/Coding/sideBar/scripts/test.sh` - Test runner wrapper
5. `/Users/sean/Coding/sideBar/scripts/migrate.sh` - Database migration helper
6. `/Users/sean/Coding/sideBar/docs/LOCAL_DEVELOPMENT.md` - Developer guide

### Files to Modify
1. `/Users/sean/Coding/sideBar/frontend/vite.config.ts` - Make proxy target environment-aware
2. `/Users/sean/Coding/sideBar/frontend/src/lib/services/api.ts` - Update SSR API URLs for local dev
3. `/Users/sean/Coding/sideBar/.gitignore` - Add `.env.local` pattern
4. `/Users/sean/Coding/sideBar/README.md` - Add local development section
5. `/Users/sean/Coding/sideBar/frontend/src/lib/server/api.ts` - Ensure API base URL is driven by `API_URL` for SSR
6. `/Users/sean/Coding/sideBar/backend/api/auth.py` - Guard `AUTH_DEV_MODE` against non-local environments
7. `/Users/sean/Coding/sideBar/backend/api/main.py` - Guard auth bypass middleware for non-local environments

## Implementation Steps

### Step 1: Environment Configuration

**Create `.env.local`:**
```bash
# Development mode - skip JWT validation for rapid iteration
AUTH_DEV_MODE=true
DEFAULT_USER_ID=81326b53-b7eb-42e2-b645-0c03cb5d5dd4

# SSR API base URL for SvelteKit server routes
API_URL=http://localhost:8001

# Explicitly mark local environment
APP_ENV=local

# All other variables (Supabase, R2, API keys) should be copied from your existing .env file
# This file extends .env - only override what's different for local dev
```

**Update `.gitignore`:**
Add `.env.local` to the ignore list to prevent committing local credentials.

### Step 2: Frontend Configuration Changes

**Modify `vite.config.ts`:**
Prefer one of these approaches:
1) **Remove the proxy entirely** and rely on SvelteKit server routes (`/api/*`) which already proxy to the backend via `API_URL`.
2) **If keeping the proxy**, do not strip `/api` from the path:
```typescript
proxy: {
  '/api': {
    target: 'http://localhost:8001',
    changeOrigin: true
  }
}
```

**Modify `api.ts` - Update all three API classes (optional):**

For `ConversationsAPI` (line 9-13):
```typescript
private get baseUrl(): string {
  return '/api/conversations';
}
```

Apply the same pattern to `NotesAPI` (line 133-135) and `WebsitesAPI` (line 171-173), adjusting the endpoint paths.

**Confirm `frontend/src/lib/server/api.ts` uses `API_URL`:**
```typescript
export function getApiUrl(): string {
  return env.API_URL || 'http://skills-api:8001';
}
```

### Step 3: Create Main Development Script

**Create `dev.sh`** with the following features:
- Load environment from `.env.local` or fallback to `.env`
- Check for port conflicts (8001, 3000)
- Start backend with `uv run uvicorn api.main:app --reload --port 8001 --host 0.0.0.0`
- Start frontend with `npm run dev`
- Capture PIDs and logs to `/tmp/sidebar-{backend,frontend}.{log,pid}`
- Commands: `start`, `stop`, `restart`, `status`, `logs [backend|frontend]`
- Make executable: `chmod +x dev.sh`

### Step 4: Create Utility Scripts

**Create `scripts/health-check.sh`:**
- Verify prerequisites: python3, node, npm, uv installed
- Check Python venv exists and has dependencies
- Check frontend node_modules exists
- Verify critical environment variables are set
- Test database connectivity
- Check port availability (8001, 3000)
- Exit with clear error/success message

**Create `scripts/test.sh`:**
```bash
#!/bin/bash
# Run tests for backend and/or frontend
# Usage: ./scripts/test.sh [backend|frontend|all]
```

**Create `scripts/migrate.sh`:**
```bash
#!/bin/bash
# Database migration helper
# Commands: upgrade, downgrade [revision], create 'message', history, current
# Sources .env.local or .env before running alembic
# If production Supabase is detected, require ALLOW_PROD_MIGRATIONS=true
```

All scripts should be executable: `chmod +x scripts/*.sh`

### Step 5: Documentation

**Create `docs/LOCAL_DEVELOPMENT.md`:**
- Quick start guide
- Environment setup instructions
- Daily workflow
- Common commands reference
- Troubleshooting tips
- Safety warnings for production DB/R2

**Update `README.md`:**
Add section after "Quick Start" with:
```markdown
## Local Development (Native)

For rapid iteration without Docker:

```bash
# First time setup
cp .env.example .env.local
# Edit .env.local with your credentials
./scripts/health-check.sh
./scripts/migrate.sh upgrade
./dev.sh start
```

See [docs/LOCAL_DEVELOPMENT.md](./docs/LOCAL_DEVELOPMENT.md) for detailed guide.
```

## Safety Considerations

### ⚠️ CRITICAL WARNING: Production Database & Storage
You're using **production infrastructure** for local development. This means:

1. **All database changes are PERMANENT** - no undo for deletions
2. **R2 file operations affect production** - uploads/deletes are real
3. **Real user data visible** - conversations, notes, files from production

### Recommended Safety Practices

1. **Use AUTH_DEV_MODE with a test user:**
   - Set `AUTH_DEV_MODE=true` to skip JWT validation
   - Set `DEFAULT_USER_ID` to a dedicated test user account
   - All dev work scoped to that user only

2. **Prefix development data:**
   - Use `[DEV]` prefix for conversation titles
   - Makes it easy to identify and clean up test data

3. **Be cautious with deletions:**
   - Double-check before deleting anything
   - Consider creating a separate Supabase dev project long-term

4. **R2 file organization:**
   - Files are organized by user ID automatically
   - Test user's files won't clutter other user spaces

5. **Guard auth bypass in non-local environments:**
   - Only allow `AUTH_DEV_MODE=true` when `APP_ENV=local`
   - Log a warning and refuse to start otherwise

## Development Workflow

### Initial Setup (First Time)
```bash
# 1. Create local environment
cp .env.example .env.local
# Edit .env.local: set AUTH_DEV_MODE=true, add credentials, set API_URL and APP_ENV=local

# 2. Install dependencies
cd backend && uv sync && cd ..
cd frontend && npm install && cd ..

# 3. Verify setup
./scripts/health-check.sh

# 4. Run migrations
./scripts/migrate.sh upgrade

# 5. Start development
./dev.sh start
```

### Daily Workflow
```bash
# Ensure on dev branch
git checkout dev

# Start development servers
./dev.sh start

# Make changes - hot reload is instant!
# Backend: uvicorn --reload watches Python files
# Frontend: Vite HMR updates browser automatically

# Check status
./dev.sh status

# View logs
./dev.sh logs              # All logs
./dev.sh logs backend      # Backend only
./dev.sh logs frontend     # Frontend only

# Run tests before committing
./scripts/test.sh all

# Stop when done
./dev.sh stop
```

### Git Workflow (dev → main)
```bash
# Work on dev branch
git checkout dev
git pull origin dev

# Develop and test
./dev.sh start
# ... make changes ...
./scripts/test.sh all

# Commit to dev
git add .
git commit -m "feat: your feature"
git push origin dev

# When ready for production
git checkout main
git pull origin main
git merge dev
git push origin main  # Triggers auto-deploy to Vercel & Fly.io

# Return to dev
git checkout dev
```

### Common Tasks

**Run Tests:**
```bash
./scripts/test.sh all         # All tests
./scripts/test.sh backend     # Backend only
./scripts/test.sh frontend    # Frontend only
```

**Database Migrations:**
```bash
./scripts/migrate.sh upgrade           # Apply all pending
./scripts/migrate.sh create "message"  # Create new migration
./scripts/migrate.sh current           # Show current version
./scripts/migrate.sh downgrade         # Rollback one version
```

**Dependency Updates:**
```bash
# Backend dependencies changed
cd backend && uv sync

# Frontend dependencies changed
cd frontend && npm install
```

## Expected Behavior After Setup

### Hot Reload Performance
- **Backend changes**: < 1 second reload (uvicorn --reload)
- **Frontend changes**: < 500ms (Vite HMR with instant browser update)
- **No Docker rebuilds needed** - instant feedback loop

### Development URLs
- **Frontend**: http://localhost:3000
- **Backend**: http://localhost:8001
- **API Docs**: http://localhost:8001/docs

### Service Status
```bash
$ ./dev.sh status
Service Status:
✓ Backend running (PID: 12345)
  URL: http://localhost:8001
  Logs: /tmp/sidebar-backend.log
✓ Frontend running (PID: 12346)
  URL: http://localhost:3000
  Logs: /tmp/sidebar-frontend.log
```

## Troubleshooting

### Port Already in Use
```bash
# Find and kill process
lsof -i :8001  # or :3000
kill -9 <PID>

# Or use dev script
./dev.sh stop
```

### Backend Won't Start
```bash
# Check logs
tail -f /tmp/sidebar-backend.log

# Verify dependencies
cd backend && uv sync

# Test database connection
cd backend && uv run python -c "from api.config import settings; print(settings.database_url)"
```

### Frontend Proxy Not Working
```bash
# Verify API_URL is set (SSR)
echo $API_URL  # Should be http://localhost:8001

# Check backend is running
curl http://localhost:8001/api/health

# Restart both services
./dev.sh restart
```

### Database Connection Failed
```bash
# Verify Supabase credentials in .env.local
# Check Supabase dashboard for IP allowlist
# Ensure your IP is not blocked
```

## Implementation Checklist

### Phase 1: Core Setup
- [ ] Create `.env.local` with AUTH_DEV_MODE=true, API_URL, and APP_ENV=local
- [ ] Update `.gitignore` to exclude `.env.local`
- [ ] Create `dev.sh` startup script (make executable)
- [ ] Create `scripts/health-check.sh` (make executable)

### Phase 2: Frontend Configuration
- [ ] Update `frontend/vite.config.ts` proxy target
- [ ] Update `frontend/src/lib/services/api.ts` for all three API classes (if needed)
- [ ] Confirm `frontend/src/lib/server/api.ts` reads `API_URL`
- [ ] Test frontend can reach backend at localhost:8001

### Phase 3: Utility Scripts
- [ ] Create `scripts/test.sh` (make executable)
- [ ] Create `scripts/migrate.sh` (make executable)
- [ ] Test all scripts work correctly

### Phase 4: Documentation
- [ ] Create `docs/LOCAL_DEVELOPMENT.md`
- [ ] Update main `README.md` with local dev section
- [ ] Add safety warnings for production DB/R2

### Phase 5: Testing & Validation
- [ ] Run `./scripts/health-check.sh` - should pass
- [ ] Run `./dev.sh start` - both services should start
- [ ] Test hot reload: change Python file, verify backend reloads
- [ ] Test hot reload: change Svelte component, verify browser updates
- [ ] Test API calls: frontend → backend → Supabase
- [ ] Test file operations: upload to R2
- [ ] Verify logs are captured in /tmp files

## Success Criteria

✅ **Setup complete when:**
1. `./dev.sh start` launches both services without errors
2. Backend hot reloads on Python file changes (< 1 second)
3. Frontend HMR updates browser on Svelte changes (< 500ms)
4. API calls flow: browser → SvelteKit route → uvicorn → Supabase
5. No Docker containers needed for development
6. All tests pass: `./scripts/test.sh all`

✅ **Workflow validated when:**
1. Can develop on `dev` branch with instant feedback
2. Can run tests before committing
3. Can merge `dev` to `main` for production deploy
4. Production infrastructure remains stable during dev

---

**Estimated Implementation Time:** ~2 hours
**Key Benefit:** Instant hot reload with zero Docker rebuild overhead
