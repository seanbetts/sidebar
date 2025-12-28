# Supabase Auth Integration Plan

## Overview

Integrate Supabase Auth to replace the current placeholder bearer token authentication with production-ready JWT-based authentication.

**Initial deployment**: Locked down to admin-only access (signups disabled). Login-only implementation for controlled access. Signup forms and OAuth can be added later when ready to onboard additional users.

## Current State

- **Backend**: FastAPI with simple bearer token validation
- **Frontend**: SvelteKit with server-side proxy routes
- **User ID**: Header-based extraction with hardcoded default UUID (`81326b53-b7eb-42e2-b645-0c03cb5d5dd4`)
- **Database**: Supabase PostgreSQL with RLS already enabled and working
- **User Scoping**: Production-ready pattern - all services filter by `user_id` parameter
- **Production Data**: Exists and needs migration to authenticated users

## Implementation Phases

### Phase 1: Backend JWT Validation

Replace bearer token auth with Supabase JWT validation.

#### 1.1 Add Dependencies

**File**: `/Users/sean/Coding/sideBar/backend/pyproject.toml`

Add:
```
PyJWT[crypto]>=2.8.0
cryptography>=41.0.0
httpx>=0.27.0
```

#### 1.2 Create JWT Validator

**New file**: `/Users/sean/Coding/sideBar/backend/api/auth/supabase_jwt.py`

Implement Supabase JWT validator that:
- Fetches JWKS from Supabase with caching (1 hour TTL) using `httpx`
- Validates JWT signature using RS256 algorithm
- Verifies token expiry, issuer, and audience
- Extracts user ID from `sub` claim
- Returns decoded payload

Key functions:
- `SupabaseJWTValidator.__init__()` - Initialize with Supabase project URL
- `SupabaseJWTValidator._fetch_jwks()` - Fetch/cache JWKS from Supabase
- `SupabaseJWTValidator.validate_token(token: str) -> dict` - Main validation logic

#### 1.3 Update Configuration

**File**: `/Users/sean/Coding/sideBar/backend/api/config.py`

Add Supabase Auth settings:
```python
# Supabase Auth
supabase_url: str  # Full Supabase URL, not computed
supabase_anon_key: str  # Public key for client-side
supabase_service_role_key: str | None = None  # Admin operations

# JWT validation
jwt_audience: str = "authenticated"
jwt_algorithm: str = "RS256"
jwks_cache_ttl_seconds: int = 3600
jwt_issuer: str = ""  # Computed from SUPABASE_URL + "/auth/v1"

# Development mode
auth_dev_mode: bool = False  # Bypass JWT for testing
```

Environment variables:
```bash
SUPABASE_URL=https://[project_id].supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
AUTH_DEV_MODE=false
```

#### 1.4 Update User ID Extraction

**File**: `/Users/sean/Coding/sideBar/backend/api/db/dependencies.py`

Replace header-based extraction with JWT validation:
```python
async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
) -> str:
    """Extract user ID from Supabase JWT token."""
    # Dev mode bypass
    if settings.auth_dev_mode:
        return DEFAULT_USER_ID

    # Validate JWT and extract user_id
    validator = SupabaseJWTValidator()
    payload = await validator.validate_token(credentials.credentials)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(401, "Invalid token: missing user ID")

    return user_id
```

Keep `DEFAULT_USER_ID` for development mode fallback.

#### 1.5 Update Auth Middleware

**File**: `/Users/sean/Coding/sideBar/backend/api/auth.py`

Replace `verify_bearer_token` with `verify_supabase_jwt`:
```python
async def verify_supabase_jwt(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme)
) -> dict:
    """Verify Supabase JWT token and return payload."""
    if settings.auth_dev_mode:
        return {"sub": DEFAULT_USER_ID}

    validator = SupabaseJWTValidator()
    try:
        payload = await validator.validate_token(credentials.credentials)
        return payload
    except JWTError as e:
        raise HTTPException(
            status_code=401,
            detail=f"Invalid JWT: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"}
        )
```

**No changes needed** to:
- `/Users/sean/Coding/sideBar/backend/api/db/session.py` - RLS session setup works as-is
- Service layer files - already filter by `user_id` parameter
- Tool execution - already accepts `--user-id` flag

#### 1.6 Understanding the Authentication Flow (No Code Changes)

**How JWT authentication connects to PostgreSQL RLS:**

1. **Request arrives** with JWT in `Authorization: Bearer {token}` header

2. **JWT validation** (`get_current_user_id` dependency):
   ```python
   # Extracts user_id from JWT 'sub' claim
   user_id = "81326b53-b7eb-42e2-b645-0c03cb5d5dd4"  # UUID from token
   ```

3. **Database session initialization** (`get_db` dependency):
   ```python
   def get_db(user_id: str = Depends(get_current_user_id)):
       db = SessionLocal()
       set_session_user_id(db, user_id)  # Sets PostgreSQL session variable
       yield db
   ```

4. **PostgreSQL session variable set** (`set_session_user_id` function):
   ```python
   def set_session_user_id(db: Session, user_id: str):
       db.execute(text("SET app.user_id = :user_id"), {"user_id": user_id})
   ```
   This executes: `SET app.user_id = '81326b53-b7eb-42e2-b645-0c03cb5d5dd4'`

5. **RLS policies enforce isolation** (already configured in migration 012):
   ```sql
   CREATE POLICY user_isolation ON notes
   FOR ALL
   USING (user_id = current_setting('app.user_id', true));
   ```
   Every query automatically filters: `WHERE user_id = current_setting('app.user_id')`

6. **SQLAlchemy queries inherit RLS** - all queries through this session are automatically scoped:
   ```python
   # This query only returns notes for authenticated user
   notes = db.query(Note).filter(Note.deleted_at.is_(None)).all()
   # PostgreSQL enforces: WHERE user_id = '81326b53-...' AND deleted_at IS NULL
   ```

**Key insight**: By switching from header-based to JWT-based extraction in `get_current_user_id`, the entire downstream flow (session variable → RLS → query scoping) continues to work identically. The RLS policies don't care WHERE the user_id came from, only that it's set in the session.

### Phase 2: Frontend Session Management

Add Supabase client and session handling to SvelteKit.

#### 2.1 Install Dependencies

**File**: `/Users/sean/Coding/sideBar/frontend/package.json`

Add:
```json
{
  "dependencies": {
    "@supabase/supabase-js": "^2.39.0",
    "@supabase/ssr": "^0.1.0"
  }
}
```

Run: `npm install`

#### 2.2 Create Supabase Clients

**New file**: `/Users/sean/Coding/sideBar/frontend/src/lib/server/supabase.ts`

Server-side client factory:
```typescript
import { createServerClient } from '@supabase/ssr';
import { env } from '$env/dynamic/private';

export function createSupabaseServerClient(cookies: any) {
  return createServerClient(
    env.SUPABASE_URL,
    env.SUPABASE_ANON_KEY,
    {
      cookies: {
        get: (key: string) => cookies.get(key),
        set: (key: string, value: string, options: any) => {
          cookies.set(key, value, { ...options, path: '/' });
        },
        remove: (key: string, options: any) => {
          cookies.delete(key, { ...options, path: '/' });
        }
      }
    }
  );
}
```

**New file**: `/Users/sean/Coding/sideBar/frontend/src/lib/supabase.ts`

Browser-side client (initialized from load data):
```typescript
import { createBrowserClient } from '@supabase/ssr';
import type { SupabaseClient } from '@supabase/supabase-js';

let supabaseClient: SupabaseClient | null = null;

export function initSupabaseClient(url: string, anonKey: string): SupabaseClient {
  if (!supabaseClient) {
    supabaseClient = createBrowserClient(url, anonKey);
  }
  return supabaseClient;
}

export function getSupabaseClient(): SupabaseClient {
  if (!supabaseClient) {
    throw new Error('Supabase client not initialized');
  }
  return supabaseClient;
}
```

#### 2.3 Session Hooks

**New file**: `/Users/sean/Coding/sideBar/frontend/src/hooks.server.ts`

Handle session validation on every request:
```typescript
import { createSupabaseServerClient } from '$lib/server/supabase';
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.supabase = createSupabaseServerClient(event.cookies);

  const { data: { session } } = await event.locals.supabase.auth.getSession();
  event.locals.session = session;

  if (session) {
    const { data: { user } } = await event.locals.supabase.auth.getUser();
    event.locals.user = user;
  }

  return resolve(event);
};
```

**File**: `/Users/sean/Coding/sideBar/frontend/src/app.d.ts`

Add type definitions:
```typescript
import type { Session, SupabaseClient, User } from '@supabase/supabase-js';

declare global {
  namespace App {
    interface Locals {
      supabase: SupabaseClient;
      session: Session | null;
      user: User | null;
    }
  }
}
```

#### 2.4 Update Root Layout

**File**: `/Users/sean/Coding/sideBar/frontend/src/routes/+layout.server.ts`

Load session for all routes:
```typescript
import { env } from '$env/dynamic/private';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals }) => {
  return {
    maintenanceMode: env.MAINTENANCE_MODE === 'true',
    supabaseUrl: env.SUPABASE_URL,
    supabaseAnonKey: env.SUPABASE_ANON_KEY,
    session: locals.session,
    user: locals.user
  };
};
```

**File**: `/Users/sean/Coding/sideBar/frontend/src/routes/+layout.svelte`

Initialize auth store:
```svelte
<script lang="ts">
  import { initAuth } from '$lib/stores/auth';
  import { onMount } from 'svelte';

  let { data } = $props();

  onMount(() => {
    initAuth(data.session, data.user, data.supabaseUrl, data.supabaseAnonKey);
  });
</script>

{#if data.maintenanceMode}
  <HoldingPage />
{:else if !data.session}
  <!-- Redirect to login handled by route guards -->
  <slot />
{:else}
  <div class="app" data-sveltekit-preload-code="tap" data-sveltekit-preload-data="tap">
    <!-- existing app structure -->
  </div>
{/if}
```

#### 2.5 Create Auth Store

**New file**: `/Users/sean/Coding/sideBar/frontend/src/lib/stores/auth.ts`

Reactive auth state:
```typescript
import { writable } from 'svelte/store';
import type { Session, User } from '@supabase/supabase-js';
import { initSupabaseClient } from '$lib/supabase';

export const session = writable<Session | null>(null);
export const user = writable<User | null>(null);

export function initAuth(
  initialSession: Session | null,
  initialUser: User | null,
  supabaseUrl: string,
  supabaseAnonKey: string
) {
  const supabase = initSupabaseClient(supabaseUrl, supabaseAnonKey);
  session.set(initialSession);
  user.set(initialUser);

  supabase.auth.onAuthStateChange((event, newSession) => {
    session.set(newSession);
    user.set(newSession?.user ?? null);
  });
}
```

#### 2.6 Update API Proxy Routes

**Pattern for ALL files in `/Users/sean/Coding/sideBar/frontend/src/routes/api/`**

Replace static `BEARER_TOKEN` with user's JWT:

```typescript
import type { RequestHandler } from './$types';
import { error } from '@sveltejs/kit';

import { env } from '$env/dynamic/private';
const API_URL = env.API_URL || 'http://skills-api:8001';

export const GET: RequestHandler = async ({ locals }) => {
  if (!locals.session) {
    throw error(401, 'Unauthorized');
  }

  const response = await fetch(`${API_URL}/api/[endpoint]`, {
    headers: {
      Authorization: `Bearer ${locals.session.access_token}`
    }
  });

  if (!response.ok) {
    throw error(response.status, `Backend error: ${response.statusText}`);
  }

  return new Response(await response.text(), {
    headers: { 'Content-Type': 'application/json' }
  });
};
```

Apply to ~35 proxy routes:
- `/api/settings/+server.ts`
- `/api/conversations/+server.ts`
- `/api/notes/**/+server.ts`
- `/api/websites/**/+server.ts`
- `/api/memories/**/+server.ts`
- `/api/files/**/+server.ts`
- `/api/chat/+server.ts`
- All others in `/api/` directory

### Phase 3: Authentication UI (Login Only)

**Note**: Initially implementing login-only. Signups are disabled in Supabase dashboard. Signup forms and OAuth can be added later.

#### 3.1 Login Component

**New file**: `/Users/sean/Coding/sideBar/frontend/src/lib/components/auth/LoginForm.svelte`

Simple email/password login (no OAuth buttons initially):
```svelte
<script lang="ts">
  import { supabase } from '$lib/supabase';
  import { goto } from '$app/navigation';

  let email = $state('');
  let password = $state('');
  let loading = $state(false);
  let error = $state('');

  async function handleLogin() {
    loading = true;
    error = '';

    const { error: authError } = await supabase.auth.signInWithPassword({
      email,
      password
    });

    if (authError) {
      error = authError.message;
      loading = false;
    } else {
      goto('/');
    }
  }
</script>

<div class="login-container">
  <h2>Sign in to sideBar</h2>

  {#if error}
    <div class="error">{error}</div>
  {/if}

  <form onsubmit={handleLogin}>
    <input type="email" bind:value={email} placeholder="Email" required />
    <input type="password" bind:value={password} placeholder="Password" required />
    <button type="submit" disabled={loading}>
      {loading ? 'Signing in...' : 'Sign in'}
    </button>
  </form>
</div>

<style>
  .login-container {
    max-width: 400px;
    margin: 4rem auto;
    padding: 2rem;
  }

  h2 {
    margin-bottom: 1.5rem;
  }

  .error {
    padding: 0.75rem;
    margin-bottom: 1rem;
    background: #fee;
    border: 1px solid #fcc;
    border-radius: 4px;
    color: #c00;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  input {
    padding: 0.75rem;
    border: 1px solid #ddd;
    border-radius: 4px;
    font-size: 1rem;
  }

  button {
    padding: 0.75rem;
    background: #000;
    color: #fff;
    border: none;
    border-radius: 4px;
    font-size: 1rem;
    cursor: pointer;
  }

  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>
```

#### 3.2 Auth Routes

**New file**: `/Users/sean/Coding/sideBar/frontend/src/routes/auth/login/+page.svelte`
```svelte
<script>
  import LoginForm from '$lib/components/auth/LoginForm.svelte';
</script>

<LoginForm />
```

**Note**: No signup route created. No OAuth callback needed initially.

#### 3.4 Route Guards

**New file**: `/Users/sean/Coding/sideBar/frontend/src/routes/(authenticated)/+layout.server.ts`

Protect all app routes:
```typescript
import { redirect } from '@sveltejs/kit';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ locals, url }) => {
  if (!locals.session) {
    throw redirect(303, `/auth/login?redirectTo=${url.pathname}`);
  }

  return {
    session: locals.session,
    user: locals.user
  };
};
```

**Restructure routes**:
- Move `/src/routes/+page.svelte` → `/src/routes/(authenticated)/+page.svelte`
- Keep `/src/routes/auth/*` outside for public access
- All app routes now require authentication

#### 3.5 Logout

**New file**: `/Users/sean/Coding/sideBar/frontend/src/routes/auth/logout/+server.ts`
```typescript
import { redirect } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ locals }) => {
  await locals.supabase.auth.signOut();
  throw redirect(303, '/auth/login');
};
```

Add logout button to header/sidebar.

### Phase 4: Supabase Configuration

#### 4.1 Supabase Dashboard Setup

**Authentication Settings**:
1. Navigate to Authentication → Providers
2. Enable Email provider (already enabled by default)
3. **DISABLE email signups**:
   - Go to Authentication → Settings
   - Toggle **OFF** "Enable email signups"
   - This prevents new user registration while keeping login working
4. **Skip OAuth setup** for now (can add Google/GitHub later when ready)

**URL Configuration**:
- Site URL: `https://sidebar.seanbetts.com`
- Redirect URLs not needed initially (no OAuth or email verification flows)

**Email Templates**:
Not needed initially since signups are disabled.

#### 4.2 Environment Variables

**Backend** (`/Users/sean/Coding/sideBar/backend/.env`):
```bash
# Supabase Auth (NEW)
SUPABASE_URL=https://[project_id].supabase.co
SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...
AUTH_DEV_MODE=false

# Keep existing Supabase DB vars
SUPABASE_PROJECT_ID=[project_id]
SUPABASE_POSTGRES_PSWD=[password]
# ... rest unchanged
```

**Frontend** (`/Users/sean/Coding/sideBar/.env`):
```bash
# Supabase Auth (shared with frontend via load)
SUPABASE_URL=https://[project_id].supabase.co
SUPABASE_ANON_KEY=eyJ...

# Existing vars
API_URL=http://skills-api:8001
MAINTENANCE_MODE=false
```

**Get keys from**:
- Supabase Dashboard → Project Settings → API
- `anon` key = SUPABASE_ANON_KEY
- `service_role` key = SUPABASE_SERVICE_ROLE_KEY

### Phase 5: Create Admin User

Since you have production data associated with the default user ID, create a Supabase auth user with matching UUID.

#### 5.1 Create Admin User with Default UUID (Recommended)

**Method 1: Using Supabase Dashboard** (Easiest)
1. Go to Authentication → Users
2. Click "Add user"
3. Enter your email and create a password
4. After user is created, note the UUID
5. You'll need to migrate data to this UUID OR use Method 2 below

**Method 2: Admin API with Service Role** (Preserves existing data)

Use the Supabase Admin API (service role) to create a user with a fixed UUID.
This avoids manual SQL inserts that can miss `auth.identities` rows or triggers.

If you *do* choose SQL later, ensure you also create a matching `auth.identities`
row and handle `raw_user_meta_data` and triggers correctly.

This preserves all existing data without migration.

**Benefits of Method 2**:
- No data migration needed
- Zero downtime
- Existing data automatically accessible to admin user
- Production data (notes, conversations, etc.) immediately available

**After setup**: You can change password through:
- Supabase Dashboard → Authentication → Users
- Or use password reset flow

#### 5.2 Alternative: Migrate Data to New User

If you prefer a clean new user ID:

**Migration script**:
```python
# Script to migrate data from default UUID to authenticated user
from sqlalchemy import text
from backend.api.db.session import SessionLocal

OLD_USER_ID = "81326b53-b7eb-42e2-b645-0c03cb5d5dd4"
NEW_USER_ID = "authenticated-user-uuid-here"

db = SessionLocal()
try:
    # Migrate each user-scoped table
    tables = [
        'notes', 'websites', 'conversations',
        'user_settings', 'user_memories', 'files'
    ]

    for table in tables:
        db.execute(
            text(f"UPDATE {table} SET user_id = :new WHERE user_id = :old"),
            {"new": NEW_USER_ID, "old": OLD_USER_ID}
        )

    db.commit()
    print("Migration complete")
except Exception as e:
    db.rollback()
    print(f"Migration failed: {e}")
finally:
    db.close()
```

**Recommendation**: Use Admin API to create user with matching UUID for simplicity and correctness.

### Phase 6: Testing & Rollout

#### 6.1 Testing Checklist

**Backend Testing**:
- [ ] JWT validation with valid Supabase token
- [ ] JWT validation with expired token (should fail)
- [ ] JWT validation with invalid signature (should fail)
- [ ] User ID extraction from JWT `sub` claim
- [ ] RLS policies work with JWT-derived user_id
- [ ] Dev mode bypass works with AUTH_DEV_MODE=true

**Frontend Testing**:
- [ ] Login with admin email/password
- [ ] Login with wrong password (should fail)
- [ ] Protected routes redirect to login when unauthenticated
- [ ] Session persists across page refreshes
- [ ] Logout clears session
- [ ] Token auto-refresh before expiry
- [ ] Signup attempts fail (signups disabled)

**User Scoping Testing**:
- [ ] Create note as User A - only User A can see it
- [ ] Create website as User B - only User B can see it
- [ ] List conversations shows only user's conversations
- [ ] Settings update only affects current user

#### 6.2 Development Workflow

**Initial Setup**:
```bash
# Backend
cd backend
pip install -r requirements.txt
# Update .env with Supabase keys
docker-compose up -d  # Start backend

# Frontend
cd frontend
npm install
# Update .env with public Supabase keys
npm run dev  # Start frontend
```

**Testing Auth**:
1. Create admin user in Supabase (see Phase 5)
2. Navigate to `http://localhost:5173/auth/login`
3. Login with admin credentials
4. Verify you're redirected to app
5. Create a note → verify it's scoped to your user ID
6. Verify existing production data is accessible
7. Logout → verify redirect to login
8. Login again → verify session persists

#### 6.3 Deployment Sequence

**Stage 1: Backend Deployment**
1. Deploy backend with JWT validation code
2. Set `AUTH_DEV_MODE=true` initially (allows testing)
3. Test JWT validation with Supabase tokens
4. Verify RLS continues to work
5. Keep old bearer token route active for rollback

**Stage 2: Frontend Deployment**
1. Deploy auth UI (login only) and session handling
2. Test login flow in production
3. Confirm session persistence
4. Verify signup is disabled

**Stage 3: Create Admin User**
1. Create Supabase user with default UUID (see Phase 5)
2. Test that production data is accessible
3. Verify no data loss
4. Confirm login works with new credentials

**Stage 4: Enable Auth**
1. Set `AUTH_DEV_MODE=false` in production
2. All users must authenticate
3. Monitor error logs
4. Have rollback plan ready (set AUTH_DEV_MODE=true)

**Stage 5: Cleanup**
1. Remove `BEARER_TOKEN` environment variable
2. Remove development mode code paths
3. Update documentation

#### 6.4 Rollback Plan

If issues occur:
1. Set `AUTH_DEV_MODE=true` in backend
2. Restore `BEARER_TOKEN` environment variable
3. Frontend will continue to work with old pattern
4. Investigate and fix issues
5. Re-enable when ready

## Critical Files Summary

### Backend Files to Create/Modify
- **CREATE**: `/Users/sean/Coding/sideBar/backend/api/auth/supabase_jwt.py` - JWT validator
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/api/config.py` - Add Supabase auth config
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/api/db/dependencies.py` - JWT-based user ID extraction
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/api/auth.py` - Replace bearer token with JWT
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/requirements.txt` - Add PyJWT, cryptography

### Frontend Files to Create/Modify
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/hooks.server.ts` - Session handling
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/lib/server/supabase.ts` - Server client
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/lib/supabase.ts` - Browser client
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/lib/stores/auth.ts` - Auth store
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/lib/components/auth/LoginForm.svelte` - Login UI (email/password only)
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/routes/auth/login/+page.svelte` - Login page
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/routes/auth/logout/+server.ts` - Logout handler
- **CREATE**: `/Users/sean/Coding/sideBar/frontend/src/routes/(authenticated)/+layout.server.ts` - Route guard
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/src/routes/+layout.server.ts` - Load session
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/src/routes/+layout.svelte` - Initialize auth
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/src/app.d.ts` - Type definitions
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/package.json` - Add Supabase dependencies
- **MODIFY**: All 35+ files in `/Users/sean/Coding/sideBar/frontend/src/routes/api/` - Use JWT from session

### Configuration Files
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/.env` - Supabase auth keys
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/.env` - Public Supabase keys
- **MODIFY**: `/Users/sean/Coding/sideBar/backend/.env.example` - Document new vars
- **MODIFY**: `/Users/sean/Coding/sideBar/frontend/.env.example` - Document new vars

## Success Criteria

- [ ] Admin can login with email/password
- [ ] Signups are disabled in Supabase dashboard
- [ ] Backend validates Supabase JWTs correctly
- [ ] User data is properly scoped (no data leakage between users)
- [ ] Sessions persist across page refreshes
- [ ] Tokens auto-refresh before expiry
- [ ] Logout works and clears session
- [ ] Production data accessible to authenticated admin user
- [ ] Protected routes require authentication
- [ ] Unauthenticated users redirected to login

## Estimated Effort

- **Phase 1 (Backend)**: 2-3 hours
- **Phase 2 (Frontend Session)**: 2-3 hours
- **Phase 3 (Auth UI - Login Only)**: 1-2 hours (simplified, no signup/OAuth)
- **Phase 4 (Supabase Config)**: 30 minutes (just disable signups)
- **Phase 5 (Create Admin User)**: 30 minutes
- **Phase 6 (Testing)**: 1-2 hours

**Total**: 7-11 hours (reduced from 11-15 hours)

## Next Steps

1. Get Supabase anon and service role keys from dashboard
2. Disable signups in Supabase dashboard
3. Start with Phase 1 (backend JWT validation)
4. Test each phase thoroughly before moving to next
5. Deploy incrementally with rollback capability

## Future Enhancements (When Ready to Onboard Users)

When you're ready to allow additional users:

1. **Enable Signups**: Toggle on "Enable email signups" in Supabase dashboard
2. **Add Signup UI**: Create SignupForm.svelte component and `/auth/signup` route
3. **Enable Email Verification**: Configure email templates in Supabase
4. **Add OAuth**: Set up Google/GitHub OAuth providers
5. **Create Callback Route**: Add `/auth/callback` for OAuth and email verification

All the architecture is in place - just add the UI components and toggle settings when ready.
