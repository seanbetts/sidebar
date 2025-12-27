# Supabase Migration Plan (RLS + Multi-User Ready)

## Goals
- Move PostgreSQL from local Docker to Supabase for shared access across dev environments.
- Enforce per-user data access with RLS.
- Keep FastAPI as the primary client, with a clean path to Supabase Auth later.

## Current State (Codebase Observations)
- FastAPI uses SQLAlchemy and `DATABASE_URL` from env.
- Auth is header-based (`X-User-ID`) and defaults to `default_user`.
- `conversations`, `user_settings`, `user_memories` already store `user_id`.
- `notes` and `websites` do not store `user_id` today.

## Strategy Overview
- Add `user_id` columns to `notes` and `websites`.
- Backfill existing rows with a default user ID.
- Update all query paths to filter by `user_id`.
- Enable RLS with policies based on `current_setting('app.user_id', true)`.
- Set `SET LOCAL app.user_id = :user_id` per request in the DB session.
- Use direct Supabase connection for migrations, pooler for runtime.

## Schema Changes
1) Add `user_id` to `notes`
   - `Text` (or `String(255)`) non-null.
   - Index on `user_id` (and optionally `(user_id, deleted_at)`).
2) Add `user_id` to `websites`
   - `Text` non-null.
   - Unique constraint should become `(user_id, url)` to avoid cross-user collisions.
   - Index on `user_id`.

## Backfill Plan
- Backfill existing rows to the single existing `user_id` already present in the database.
- Use a one-time SQL migration to populate `user_id` and adjust constraints.
- Ensure all existing rows get a value before setting `NOT NULL`.

## RLS Design
- Enable RLS on all tables:
  - `notes`, `websites`, `conversations`, `user_settings`, `user_memories`
- Policy model:
  - `USING (user_id = current_setting('app.user_id', true))`
  - `WITH CHECK (user_id = current_setting('app.user_id', true))`
- App role should not have `bypassrls`.

## App Changes
1) Models
   - Add `user_id` to `Note` and `Website` models.
   - Update unique/index definitions for `Website` to include `user_id`.
2) Services/Routers
   - Every query filters by `user_id` from `get_current_user_id`.
   - Create/update paths set `user_id` explicitly.
3) Session Hook
   - After opening a DB session, run:
     - `SET LOCAL app.user_id = :user_id`
   - This should happen once per request (dependency layer).

## Supabase Setup
- Create Supabase project.
- Capture both connection strings:
  - Direct (for Alembic/migrations/admin tasks).
  - Pooler (for app runtime `DATABASE_URL`).
- Ensure SSL is required (`sslmode=require`).

## Migration Steps (Suggested Order)
1) Create and run Alembic migration locally for schema changes.
2) Apply migration to Supabase using direct connection string.
3) Copy data from local Postgres to Supabase:
   - `pg_dump --no-owner --no-acl` from local.
   - Restore into Supabase direct connection.
4) Enable RLS and policies.
5) Update app env config to Supabase pooler URL.
6) Validate via API with different `X-User-ID` values.

## Verification Checklist
- CRUD works for each table when `X-User-ID` is set.
- Cross-user access is denied.
- `notes` and `websites` enforce uniqueness per user.
- Migrations run cleanly against Supabase.

## Rollback Plan
- Keep local Docker Postgres running until Supabase is verified.
- Maintain local dump before switching `DATABASE_URL`.
- If issues, revert env vars and re-run against local DB.

## Open Questions
- Whether to adopt Supabase Auth now or later (affects policy function).
