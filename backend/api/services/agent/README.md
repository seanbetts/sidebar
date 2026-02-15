# Agent Runtime Package

This package is the consolidation point for AI agent runtime orchestration:

- `orchestrator/`: stream loop and event orchestration
- `prompt/`: prompt composition and templates
- `tools/`: tool registry, mapping, and execution hooks
- `skills/`: skill catalog and skill execution

The current files are compatibility wrappers that re-export legacy modules.
They allow incremental import cutover before moving implementations.
