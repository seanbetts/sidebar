# ADR 0002: Prompt Formatting Helpers

**Status:** Accepted
**Date:** 2026-01-04

## Context

`backend/api/prompts.py` accumulated both prompt templates and formatting helpers, making it harder to maintain.

## Decision

Split prompt config and formatting helpers into:
- `backend/api/prompt_config.py`
- `backend/api/prompt_formatters.py`

Keep prompt assembly in `backend/api/prompts.py`.

## Consequences

- Prompt helpers are reusable and easier to test.
- Prompt module size is reduced and focused on composition.

