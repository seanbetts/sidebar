# Skill Authoring Guide

This guide covers how to create a new skill that the sideBar AI agent can use, and how to register that skill in the Skills Store catalog.

## Skill Types

There are two skill types in sideBar:

- Instruction-only skills: used for guidance/discovery and catalog metadata, with no runtime tool wiring.
- Tool-backed skills: executable agent tools that map to scripts under `backend/skills/<skill-id>/scripts/`.

If users should be able to run actions through the agent, the skill must be tool-backed.

## Skill Folder Structure

Create a new folder under `backend/skills/<skill-id>/`:

```text
backend/skills/<skill-id>/
├── SKILL.md                  # required
├── scripts/                  # optional executable helpers
├── references/               # optional docs loaded on demand
└── assets/                   # optional templates/static files
```

Use lowercase letters, numbers, and hyphens for `<skill-id>`.

## Required File Template (`SKILL.md`)

```markdown
---
name: my-skill
description: Short, specific trigger guidance for when this skill should be used.
---

# my-skill

## Overview

Describe what this skill does in 1-2 sentences.

## Workflows

List the concrete workflows this skill supports.

## Resources

- `scripts/...`: deterministic execution helpers
- `references/...`: detailed docs and schemas
- `assets/...`: templates/files copied into output
```

Notes:
- Keep frontmatter keys minimal (`name`, `description`; optional metadata keys may be used if required by your tooling).
- Put trigger conditions in `description`, not only in body text.

### Detail Metadata (`metadata`)

To power the Skills Store detail modal, add fields under `metadata`:

```markdown
---
name: my-skill
description: Short trigger guidance.
metadata:
  long_description: Clear user-facing description for the detail modal.
  how_it_works: Non-technical explanation of the workflow.
  requirements:
    - Access to the source system this skill reads from
  version: 1.0.0
  updated_at: 2026-02-22
---
```

Policy:
- For Store skills, `metadata.long_description`, `metadata.how_it_works`, `metadata.version`, and `metadata.updated_at` are required.
- For required/standard skills, metadata is optional but recommended when shown in Skills UI.
- `metadata.requirements` is optional and should list only user-facing setup prerequisites.

`metadata.requirements` should only include user-facing prerequisites. Do not include:
- API key/credential requirements
- usage-time inputs (for example "a file to transcribe", "a URL to analyze")
- local runtime/setup dependencies (for example `ffmpeg`, `pip install`, `brew install`)

Credential requirements belong in `backend/api/services/tools/skill_metadata.py` (`SKILL_CREDENTIAL_REQUIREMENTS`).
Developer dependencies should stay in the body docs for maintainers.

### Source Of Truth

For Skills Store detail content, `SKILL.md` frontmatter `metadata` is the source of truth.
Do not rely on hardcoded fallback maps for long-term content.

### Validation Rules For Detail Metadata

`backend/scripts/skill_quick_validate.py` validates these metadata fields when present:

- `metadata.long_description`: non-empty string
- `metadata.how_it_works`: non-empty string
- `metadata.requirements`: list of non-empty strings
- `metadata.version`: semantic version string (for example `1.2.3`)
- `metadata.updated_at`: ISO date or datetime (for example `2026-02-22` or `2026-02-22T14:30:00Z`)

If any of these fields are invalid, skill validation will fail.
The validator also rejects `metadata.requirements` entries that look like credential or developer dependency instructions.
Store-skill metadata presence is enforced by authoring policy/review and publish checklist.

### UI Fallback Behavior

When optional detail metadata is not provided:

- `long_description` falls back to the short `description`
- `how_it_works` falls back to a generic user-friendly explanation
- `requirements` section is shown only when user-facing requirements or required credential metadata exist
- `version` and `updated_at` are omitted in the detail section

### Reserved Future Fields

The skills API also carries reserved future engagement fields:

- `install_count`
- `upvotes`
- `downvotes`
- `current_user_vote`

These are API-managed fields for future product phases. Do not author them in `SKILL.md` metadata today.

## Optional Script Template

```python
#!/usr/bin/env python3
"""One-line purpose for this helper script."""

from __future__ import annotations

import argparse
import json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    payload = {"ok": True}
    if args.json:
        print(json.dumps(payload))
    else:
        print("ok")


if __name__ == "__main__":
    main()
```

## Tool-Backed Script Contract

Tool-backed skills must follow this execution contract:

- Accept `--json`.
- Accept `--user-id` for user-scoped operations.
- Print success payload as JSON to stdout:
  - `{"success": true, "data": ...}`
- Print error payload as JSON to stderr and exit non-zero:
  - `{"success": false, "error": "..."}`
- Keep scripts deterministic and argument-driven (no hidden prompts/interactive input).

## Assistant Workspace Output (Optional)

Some tool-backed skills can also drive the dynamic Assistant Workspace in iOS/macOS.
This is optional and should be used only when the output benefits from a dedicated surface (for example rich markdown, table/chart/map previews, or interactive follow-up actions).

### When To Use

- Use chat-only output for short/simple results.
- Use workspace surfaces when users need to revisit, copy/share/export, or interact with richer content.
- Do not emit workspace patches for every skill by default.

### Result Contract

In successful tool output (`{"success": true, "data": ...}`), include one of:

- `workspace_patch`: single patch object
- `workspace_patches`: array of patch objects

Patch schema (versioned):

```json
{
  "version": 1,
  "operations": [
    {
      "op": "present_agent_surface",
      "pane": "primary",
      "surface": {
        "type": "markdown",
        "surface_id": "example-surface",
        "title": "Example",
        "payload": {
          "markdown": "# Example"
        },
        "context_menu_actions": ["copy_markdown", "share_text", "download"],
        "capabilities": {
          "can_refresh": false,
          "can_close": true
        }
      }
    }
  ]
}
```

### Supported Operations (v1)

- `present_agent_surface` (aliases accepted by clients: `upsert_agent_surface`, `update_agent_surface`)
- `close_pane`
- `set_surface_pinned`
- `swap_panes`

### Surface Fields

- `type`: `markdown`, `table`, `chart`, `map`, `form`, `actionPanel`
- `surface_id`: stable identifier for updates/reopen targeting
- `title`: optional user-facing title for header and chat action labels
- `payload`: string map used by the renderer (`markdown` key is used for markdown surfaces)
- `context_menu_actions`: optional list (`copy_markdown`, `share_text`, `download`) used to populate the header `...` menu
- `capabilities`: optional UI capability flags (`can_refresh`, `can_close`, `can_pin`, `can_inspect_data`)

### Authoring Notes

- Keep `version` as an integer (`1` currently supported).
- Unknown operations may be ignored by clients; always include at least one valid operation.
- Use deterministic `surface_id` values so users can reliably reopen/replace the same surface.
- Keep chat text useful even when a client does not render workspace surfaces.

## Register Tool-Backed Skills In Agent Runtime

Creating `backend/skills/<skill-id>/scripts/*.py` is not sufficient by itself. Wire the skill into runtime:

1. Add tool definitions in the appropriate definitions module under `backend/api/services/tools/definitions_*.py`.
2. Ensure that definitions module is aggregated by `backend/api/services/agent/tools/registry.py`.
3. Add argument builders in `backend/api/services/tools/parameter_builders/` and mapper functions in `backend/api/services/tools/parameter_mapper.py`.
4. Use `skill: "<skill-id>"` in tool definitions, matching the folder name in `backend/skills/<skill-id>/`.
5. If the tool requires per-user context, add the skill ID to `SKILLS_REQUIRING_USER_ID` in `backend/api/services/agent/tools/mapper.py`.
6. Add `validate_read` and/or `validate_write` in tool definitions when path safety is required.

## Skill ID Stability And Renames

Skill IDs are stable once shipped. Prefer introducing a new skill over renaming.

If a rename is unavoidable pre-release, perform a full sweep:

1. Rename `backend/skills/<old-id>/` to `backend/skills/<new-id>/`.
2. Update catalog metadata/tier sets and display fields in `backend/api/services/tools/skill_metadata.py`.
3. Update tool definitions/runtime wiring to the new ID.
4. Update any client logic keyed by tool names and skill IDs.
5. Add/adjust migrations for persisted settings arrays if data already exists.
6. Update tests and docs in the same change set.

## Validation Workflow

1. Initialize a new skeleton (optional but recommended):

```bash
mkdir -p backend/skills/<skill-id>
```

2. Validate the skill:

```bash
python backend/scripts/skill_quick_validate.py backend/skills/<skill-id>
```

To validate all skills at once:

```bash
for d in backend/skills/*; do
  [ -f "$d/SKILL.md" ] || continue
  python backend/scripts/skill_quick_validate.py "$d"
done
```

3. Add or update tests for behavior you introduce (for scripts and API integration).
   Minimum expected coverage for tool-backed skills:
   - `backend/tests/api/test_tool_mapper.py` (routing/filtering/execution path)
   - `backend/tests/api/test_skill_catalog_service.py`
   - `backend/tests/api/test_skills_api.py`
   - Store install/update tests when tier is `store`

## Add Skill To Skills Store Catalog

To make a skill appear in the Skills Store UI, update backend catalog metadata:

1. Add display metadata in `backend/api/services/tools/skill_metadata.py` under `SKILL_DISPLAY`.
2. Classify the skill by adding it to exactly one tier set:
   - `REQUIRED_SKILLS`
   - `STANDARD_SKILLS`
   - `STORE_SKILLS` (installable from Skills Store)
3. If it is a store skill with provider requirements, update:
   - `SKILL_PROVIDER_DEPENDENCY`
   - `SKILL_CREDENTIAL_REQUIREMENTS`
4. Ensure skill detail metadata is present in `SKILL.md` frontmatter `metadata` (`long_description`, `how_it_works`, `version`, `updated_at` required for Store skills; add `requirements` when setup prerequisites exist).
5. Bump `CATALOG_VERSION` in `backend/api/services/tools/skill_metadata.py`.
6. Add category mapping in `backend/api/services/agent/skills/catalog.py` (`_category_map`).
7. Add or update API/service tests:
   - `backend/tests/api/test_skill_catalog_service.py`
   - `backend/tests/api/test_skills_api.py`
8. If skill inventory changed, regenerate `backend/SKILLS.md`:

```bash
python backend/scripts/generate_skills_md.py
```

## iOS Presentation Updates (when applicable)

If the skill is visible in iOS Skills Store, update symbol mappings:

1. Add icon symbol mapping in `ios/sideBar/sideBar/Views/SkillsStore/SkillsStoreLogic.swift` (`skillSymbols`).
2. If you add a new category type, update category icon mapping in `ios/sideBar/sideBar/Views/SkillsStore/SkillsStoreCardComponents.swift`.

## Publish Checklist

- Skill folder exists in `backend/skills/<skill-id>/`.
- `SKILL.md` validates.
- All skills pass quick validation (local loop or CI `Skills Validation` workflow).
- Store skill includes `metadata.long_description`, `metadata.how_it_works`, `metadata.version`, and `metadata.updated_at` (`metadata.requirements` included when setup prerequisites exist).
- Tool-backed skills are wired through definitions, registry, and parameter builders/mappers.
- If workspace output is used, `workspace_patch` payloads validate against v1 schema and include at least one valid operation.
- Catalog metadata, tier, and category are updated.
- `CATALOG_VERSION` is bumped.
- Backend tests for mapper + catalog/API pass.
- `backend/SKILLS.md` is regenerated when skill inventory changes.
- UI icon/category mappings are updated where needed.
