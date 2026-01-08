# iOS API Contract Tests (Manual Checklist)

Use this as a smoke test list once the SwiftUI app can run.

## Auth
- Login via Supabase, confirm access token available.
- Make a simple API call and ensure Authorization header works.

## Chat + Conversations
- Create conversation, list conversations.
- Stream a message via SSE and confirm token streaming.
- Verify UI side-effects (note/website/theme/scratchpad) appear.
- Generate title for a conversation.

## Notes
- Load tree, open note, update content.
- Rename note, move note, pin/unpin, archive.
- Create/rename/move/delete folders.

## Scratchpad
- Load scratchpad note, append content, clear.

## Files (Workspace)
- Load tree, open file content.
- Rename/move/delete a file.

## Files (Ingestion)
- Upload a file, confirm processing status.
- Open derivative content viewer.
- Pin/unpin, rename, delete.

## Websites
- List websites, open detail.
- Quick-save URL and check job status.
- Pin/archived/rename, delete.

## Memories
- List, create, update, delete.

## Settings + Skills
- Load settings, update profile fields.
- Load skills list, update enabled skills.

## Weather + Places
- Fetch weather for a coordinate.
- Places autocomplete and reverse geocode.
