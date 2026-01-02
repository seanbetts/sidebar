# Shortcuts Share Sheet Setup (sideBar)

Target API: https://sidebar-api.fly.dev/

Use your PAT in the Authorization header:
`Authorization: Bearer sb_pat_...`

These are macOS Shortcuts that show in the Share Sheet and sync to iOS.

---

## 1) Scratchpad (prepend) — Share Sheet

**Input:** Text (enable “Show in Share Sheet”)

Steps:
1. Receive Shortcut Input (Text)
2. Get Contents of URL
   - URL: `https://sidebar-api.fly.dev/api/scratchpad`
   - Method: POST
   - Headers:
     - `Authorization` = `Bearer sb_pat_...`
     - `Content-Type` = `application/json`
   - Request Body: JSON
     - `content` = Shortcut Input
     - `mode` = `prepend`
3. Get Dictionary Value
   - Key: `error`
4. If `error` has any value
   - Show Notification
     - Title: `Scratchpad failed`
     - Body: `Could not save.`
5. Otherwise
   - Show Notification
     - Title: `Saved to Scratchpad`
     - Body: `Added to the top.`

---

## 2) Quick Note — Share Sheet

**Input:** Text

Steps:
1. Receive Shortcut Input (Text)
2. Ask for Input
   - Prompt: `Title (optional)`
   - Type: Text
3. Ask for Input
   - Prompt: `Folder (optional)`
   - Type: Text
4. Get Contents of URL
   - URL: `https://sidebar-api.fly.dev/api/notes`
   - Method: POST
   - Headers:
     - `Authorization` = `Bearer sb_pat_...`
     - `Content-Type` = `application/json`
   - Request Body: JSON
     - `title` = Title
     - `content` = Shortcut Input
     - `folder` = Folder
5. Get Dictionary Value
   - Key: `error`
6. If `error` has any value
   - Show Notification
     - Title: `Note failed`
     - Body: `Could not create note.`
7. Otherwise
   - Show Notification
     - Title: `Note saved`
     - Body: `Your note was created.`

---

## 3) Save to sideBar (URL or File) — Share Sheet

**Input:** URLs, Files

This shortcut accepts either a URL or a file and routes it to the correct endpoint.

Steps:
1. Receive Shortcut Input (URLs, Files)
2. If Shortcut Input is URL
   - Get Contents of URL
     - URL: `https://sidebar-api.fly.dev/api/websites/quick-save`
     - Method: POST
     - Headers:
       - `Authorization` = `Bearer sb_pat_...`
       - `Content-Type` = `application/json`
     - Request Body: JSON
       - `url` = Shortcut Input
   - Get Dictionary Value
     - Key: `data`
   - Get Dictionary Value
     - From `data`, key: `job_id`
   - Repeat 10 Times
     - Wait 2 seconds
     - Get Contents of URL
       - URL: `https://sidebar-api.fly.dev/api/websites/quick-save/{job_id}`
       - Method: GET
       - Headers:
         - `Authorization` = `Bearer sb_pat_...`
     - Get Dictionary Value
       - Key: `status`
     - If `status` is `failed`
       - Show Notification
         - Title: `Website save failed`
         - Body: `Could not fetch content.`
       - Exit Repeat
     - If `status` is `completed`
       - Show Notification
         - Title: `Website saved`
         - Body: `Saved to sideBar.`
       - Exit Repeat
3. Otherwise If Shortcut Input is File
   - Get Contents of URL
     - URL: `https://sidebar-api.fly.dev/api/ingestion/quick-upload`
     - Method: POST
     - Headers:
       - `Authorization` = `Bearer sb_pat_...`
     - Request Body: Form
       - Field name: `file`
       - Value: Shortcut Input
   - Get Dictionary Value
     - Key: `error`
   - If `error` has any value
     - Show Notification
       - Title: `Upload failed`
       - Body: `Could not upload file.`
   - Otherwise
     - Show Notification
       - Title: `File uploaded`
       - Body: `Ingestion started.`
4. Otherwise
   - Show Notification
     - Title: `Unsupported input`
     - Body: `Share a URL or a file.`

---

## Optional Enhancements

- Add a “Show Result” action after each request when debugging.
- For multiple URLs or files, add a “Repeat with Each” around the request and notification steps.
- Add a “Vibrate Device” action for success if using iOS.
