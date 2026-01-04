# ADR 0001: API Versioning

**Status:** Accepted
**Date:** 2026-01-04

## Context

We need a stable API surface for external clients while continuing to evolve backend routes.

## Decision

Adopt `/api/v1/*` as the primary API namespace. Legacy `/api/*` routes remain temporarily for backwards compatibility.

## Consequences

- Clients should migrate to `/api/v1`.
- Backend maintains both route sets until deprecation is complete.
- Frontend proxies through `/api/v1` by default.

