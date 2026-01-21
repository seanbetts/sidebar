# Task System Migration Implementation Plan

## Scope
Implement Phase 1 (schema + models) and Phase 2 (import scaffolding) with service-layer patterns, tests, and soft-delete/JSONB safeguards.

## Steps
1. Add alembic migration for task areas/projects/tasks + operation log with RLS and soft-delete fields.
2. Add SQLAlchemy models for TaskArea/TaskProject/Task with relationships and indexes.
3. Add base service scaffolding (TaskService + TasksImportService) returning ORM models, plus custom exceptions.
4. Add initial tests for models/services and migration sanity.
5. Verify lint/type/tests as feasible.

## Notes
- Keep service layer as sole DB access point.
- All deletes are soft deletes.
- Track JSONB modifications with flag_modified.
