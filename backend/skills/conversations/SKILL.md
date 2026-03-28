---
name: conversations
description: Search and rename saved conversations through Chat.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Conversations Skill

Search and rename saved conversations through Chat.

## Scripts

- `search_conversations.py` - Search conversations by title or visible preview text
- `rename_conversation.py` - Rename a conversation by ID

All scripts support `--json` output.
