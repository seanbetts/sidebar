## GoodLinks Parsing Phase 1 Plan

### Goal
Ship a minimal local parsing pipeline for web-save (fetch → Readability → metadata → markdown + YAML frontmatter), keep Jina fallback, and add tests.

### Steps
1. Inspect current web-save scripts/services and identify entry points to swap parsing logic.
2. Implement minimal parser modules (fetcher, readability wrapper, metadata extraction, markdown + frontmatter).
3. Wire `save_url.py` to use local parser first, fallback to Jina on failure; log parse mode to metadata_.
4. Add unit tests for parser pipeline and integration test for save_url path.
5. Run targeted tests and update docs/plan status.
