---
name: memory
description: Persistent memory operations for storing, updating, and deleting long-lived user context.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Memory

Persistent memory operations for long-lived user context.

## Use Cases

- Save facts the assistant should remember across conversations
- Update or correct previously stored memories
- Delete memories that are no longer useful or accurate

## Notes

- Memory operations are handled through the dedicated memory tool pipeline.
- Memory records are user-scoped and persisted in the database.
- Use concise, durable facts instead of transient session details.
