# File Ingestion Test Checklist

Use this checklist to verify the ingestion migration and fs tooling.

## Manual UI/Workflow Tests
- [x] Upload PDF via UI → confirm it appears in the Files sidebar list.
- [x] AI writes markdown via fs write → confirm it appears in the Files panel.
- [x] Processing status visible → open file details for both and confirm status/stage.
- [x] ai.md derivatives exist → open AI markdown view and verify frontmatter + content.
- [x] Recent activity prompt context → open a file, start chat, confirm file appears.

## Phase 1: Fast-Track
- [ ] Upload `.txt` → ready quickly, content shows.
- [ ] Upload `.md` → ready quickly, content shows.
- [ ] Upload `.json` → ready quickly, content shows.
- [ ] Verify ai.md generation for each (frontmatter + content).

## Phase 2: fs Scripts
- [ ] `list.py` → `python list.py . --pattern "*" --user-id <id> --json` returns files.
- [ ] `read.py` → `python read.py <path> --user-id <id> --json` returns ai.md content.
- [ ] `write.py` → `python write.py test.md --content "hello" --user-id <id> --json`.
- [ ] `delete.py` → `python delete.py test.md --user-id <id> --json`.
- [ ] `move.py` → `python move.py a.md b.md --user-id <id> --json`.
- [ ] `rename.py` → `python rename.py b.md c.md --user-id <id> --json`.
- [ ] `info.py` → `python info.py c.md --user-id <id> --json` shows status/stage.

## Phase 3: Paths
- [ ] Upload `folder/sub/test.txt` → appears under hierarchy.
- [ ] Move a file into `folder/sub` → path updates in UI.
- [ ] `list.py folder --recursive --user-id <id> --json` shows nested file.

## Frontend/API Spot Checks
- [x] Files panel tree renders without errors.
- [x] Search returns expected matches.
- [x] Rename/move/delete in UI updates list + viewer.
