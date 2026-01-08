# iOS Realtime and SSE Notes

## Supabase Realtime Channels
- notes: table `notes`, filter `user_id`
- websites: table `websites`, filter `user_id`
- ingested_files: table `ingested_files`, filter `user_id`
- file_processing_jobs: table `file_processing_jobs` (no filter)

## SSE Events (Chat Stream)
Required events to handle:
- token
- tool_call
- tool_result
- complete
- error
- note_created
- note_updated
- note_deleted
- website_saved
- website_deleted
- ui_theme_set
- scratchpad_updated
- scratchpad_cleared
- prompt_preview
- tool_start
- tool_end
- memory_created
- memory_updated
- memory_deleted
