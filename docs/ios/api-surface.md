# iOS API Surface (Reference)

Base URL: `/api/v1`

## Auth
- Use Supabase access token as `Authorization: Bearer <token>`

## Chat + Conversations
- `POST /chat/stream` (SSE)
- `POST /chat/generate-title`
- `GET /conversations/`
- `POST /conversations/`
- `GET /conversations/{id}`
- `PUT /conversations/{id}`
- `DELETE /conversations/{id}`
- `POST /conversations/{id}/messages`
- `POST /conversations/search?query=...&limit=...`

## Notes
- `GET /notes/tree`
- `POST /notes/search`
- `GET /notes/{id}`
- `PATCH /notes/{id}`
- `PATCH /notes/{id}/rename`
- `PATCH /notes/{id}/move`
- `PATCH /notes/{id}/archive`
- `PATCH /notes/{id}/pin`
- `PATCH /notes/pinned-order`
- `POST /notes/folders`
- `PATCH /notes/folders/rename`
- `PATCH /notes/folders/move`
- `DELETE /notes/folders`

## Scratchpad
- `GET /scratchpad`
- `POST /scratchpad`
- `DELETE /scratchpad`

## Workspace Files
- `GET /files/tree`
- `POST /files/search`
- `POST /files/folder`
- `POST /files/rename`
- `POST /files/move`
- `POST /files/delete`
- `GET /files/content`
- `POST /files/content`
- `GET /files/download`

## Ingestion Files
- `GET /ingestion`
- `POST /ingestion`
- `GET /ingestion/{file_id}/meta`
- `GET /ingestion/{file_id}/content?kind=...`
- `PATCH /ingestion/{file_id}/pin`
- `PATCH /ingestion/pinned-order`
- `PATCH /ingestion/{file_id}/rename`
- `DELETE /ingestion/{file_id}`
- `POST /ingestion/{file_id}/pause`
- `POST /ingestion/{file_id}/resume`
- `POST /ingestion/{file_id}/cancel`

## Websites
- `GET /websites`
- `POST /websites/search`
- `POST /websites/quick-save`
- `GET /websites/quick-save/{job_id}`
- `PATCH /websites/pinned-order`
- `PATCH /websites/{id}/pin`
- `PATCH /websites/{id}/archive`
- `GET /websites/{id}/download`
- `GET /websites/{id}`

## Memories
- `GET /memories`
- `POST /memories`
- `GET /memories/{id}`
- `PATCH /memories/{id}`
- `DELETE /memories/{id}`

## Settings + Skills
- `GET /settings`
- `PATCH /settings`
- `POST /settings/profile-image`
- `GET /settings/profile-image`
- `DELETE /settings/profile-image`
- `GET /settings/shortcuts/pat`
- `POST /settings/shortcuts/pat/rotate`
- `GET /skills`

## Weather + Places
- `GET /weather?lat=...&lon=...`
- `GET /places/autocomplete?query=...`
- `GET /places/reverse?lat=...&lon=...`
