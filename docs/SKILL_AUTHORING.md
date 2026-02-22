# Skill Authoring Guide

This guide covers how to create a new skill that the sideBar AI agent can use, and how to register that skill in the Skills Store catalog.

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

### Optional Detail Metadata (Recommended for Store Skills)

To power the Skills Store detail modal, add optional fields under `metadata`:

```markdown
---
name: my-skill
description: Short trigger guidance.
metadata:
  long_description: Clear user-facing description for the detail modal.
  how_it_works: Non-technical explanation of the workflow.
  requirements:
    - OpenAI API key
    - Any local/system dependencies users should know about
  version: 1.0.0
  updated_at: 2026-02-22
---
```

These fields are optional but strongly recommended for any skill that appears in the Skills Store.

### Source Of Truth

For Skills Store detail content, `SKILL.md` frontmatter `metadata` is the source of truth.
Do not rely on hardcoded fallback maps for long-term content.

### Validation Rules For Detail Metadata

`backend/skills/skill-creator/scripts/quick_validate.py` validates these optional metadata fields when present:

- `metadata.long_description`: non-empty string
- `metadata.how_it_works`: non-empty string
- `metadata.requirements`: list of non-empty strings
- `metadata.version`: semantic version string (for example `1.2.3`)
- `metadata.updated_at`: ISO date or datetime (for example `2026-02-22` or `2026-02-22T14:30:00Z`)

If any of these fields are invalid, skill validation will fail.

### UI Fallback Behavior

When optional detail metadata is not provided:

- `long_description` falls back to the short `description`
- `how_it_works` falls back to a generic user-friendly explanation
- `requirements` falls back to credential-derived requirements (or a no-special-requirements message)
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

## Validation Workflow

1. Initialize a new skeleton (optional but recommended):

```bash
python backend/skills/skill-creator/scripts/init_skill.py <skill-id> --path backend/skills
```

2. Validate the skill:

```bash
python backend/skills/skill-creator/scripts/quick_validate.py backend/skills/<skill-id>
```

3. Add or update tests for behavior you introduce (for scripts and API integration).

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
4. Ensure skill detail metadata is present in `SKILL.md` frontmatter `metadata` (recommended for all Store skills).
5. Bump `CATALOG_VERSION` in `backend/api/services/tools/skill_metadata.py`.
6. Add category mapping in `backend/api/services/agent/skills/catalog.py` (`_category_map`).
7. Add or update API/service tests:
   - `backend/tests/api/test_skill_catalog_service.py`
   - `backend/tests/api/test_skills_api.py`

## iOS Presentation Updates (when applicable)

If the skill is visible in iOS Skills Store, update symbol mappings:

1. Add icon symbol mapping in `ios/sideBar/sideBar/Views/SkillsStore/SkillsStoreLogic.swift` (`skillSymbols`).
2. If you add a new category type, update category icon mapping in `ios/sideBar/sideBar/Views/SkillsStore/SkillsStoreCardComponents.swift`.

## Publish Checklist

- Skill folder exists in `backend/skills/<skill-id>/`.
- `SKILL.md` validates.
- Store skill includes `metadata.long_description`, `metadata.how_it_works`, `metadata.requirements`, `metadata.version`, and `metadata.updated_at`.
- Catalog metadata, tier, and category are updated.
- `CATALOG_VERSION` is bumped.
- Backend tests for catalog/API pass.
- UI icon/category mappings are updated where needed.
