# Skill Refactoring Review

Analysis of all unexposed skills to determine if they need refactoring to fit the unified architecture model (service layer + database + SSE events).

**Status**: Reviewing 11 remaining skills (removed list-skills and folder-config as redundant/deprecated).

## Architecture Model Summary

**Current Pattern:**
1. **Database-backed operations** (Notes, Websites):
   - Service layer in `backend/api/services/`
   - Dual-mode scripts with `--database` flag
   - Database storage with PostgreSQL
   - SSE events for real-time UI updates
   - Visible in UI

2. **Filesystem operations** (Documents, fs tools):
   - Direct filesystem operations
   - Work within workspace boundaries
   - No database persistence
   - Not visible in UI (except through file browser)

---

## Skill-by-Skill Analysis

### 1. audio-transcribe
**Current State:**
- Takes audio file path as input
- Calls OpenAI Whisper API for transcription
- Saves transcript as `.txt` file to `~/Documents/Agent Smith/Transcripts/`
- Returns file path in JSON output

**Should it be database-backed?** 🟡 YES
- Transcripts are text content similar to notes
- Users want to search, organize, and reference transcripts
- Should be visible in UI alongside notes
- Natural fit for notes database table

**Refactoring Needed:**
- [ ] Add `--database` flag to `transcribe_audio.py`
- [ ] Create database mode that saves to notes table via NotesService
- [ ] Add folder metadata: `folder: "transcripts"` or `folder: "transcripts/audio"`
- [ ] Emit `note_created` SSE event after successful transcription
- [ ] MCP tool: `audio_transcribe` with parameters: `file_path`, `language`, `model`
- [ ] Keep filesystem mode for backward compatibility

**Priority:** HIGH - High user value, clear database fit

---

### 2. youtube-transcribe
**Current State:**
- Downloads YouTube audio using youtube-download skill
- Transcribes using audio-transcribe skill
- Saves transcript to filesystem
- Cleans up audio file unless `--keep-audio` specified

**Should it be database-backed?** 🟡 YES
- Same reasoning as audio-transcribe
- YouTube transcripts are valuable searchable content
- Should include YouTube URL and metadata in notes

**Refactoring Needed:**
- [ ] Add `--database` flag to `transcribe_youtube.py`
- [ ] Create database mode that saves to notes table
- [ ] Include YouTube URL, video title in note metadata
- [ ] Add folder: `folder: "transcripts/youtube"`
- [ ] Emit `note_created` SSE event
- [ ] MCP tool: `youtube_transcribe` with parameters: `url`, `language`, `model`
- [ ] Depends on audio-transcribe refactoring

**Priority:** HIGH - High user value, depends on audio-transcribe

---

### 3. youtube-download
**Current State:**
- Downloads YouTube videos/audio to filesystem
- Saves to `~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/` (iCloud)
- Returns file path

**Should it be database-backed?** 🔴 NO
- Downloads are binary files (video/audio)
- Not searchable text content
- Filesystem storage is appropriate
- May be used as intermediate step for transcription

**Refactoring Needed:**
- [ ] Ensure workspace path validation works correctly
- [ ] MCP tool: `youtube_download` with parameters: `url`, `format`, `output_dir`
- [ ] No database integration needed

**Priority:** MEDIUM - Useful tool, no major refactoring needed

---

### 4. docx (Word document manipulation)
**Current State:**
- Creates, edits, analyzes Word documents
- Works with `.docx` files in filesystem/workspace
- Supports tracked changes, comments, formatting

**Should it be database-backed?** 🔴 NO
- Documents are binary files, not searchable text
- Editing requires preserving complex formatting
- Filesystem storage is appropriate
- Users manage documents as files

**Refactoring Needed:**
- [ ] Ensure workspace path validation
- [ ] MCP tools: Could expose specific operations like:
  - `docx_create` - Create new document
  - `docx_read` - Extract text from document
  - `docx_edit` - Edit existing document
- [ ] No database integration needed

**Priority:** MEDIUM - Useful but complex, no major architecture changes

---

### 5. pdf (PDF manipulation)
**Current State:**
- Extract text/tables, create, merge, split, fill forms
- Multiple scripts for different PDF operations
- Works with PDF files in filesystem

**Should it be database-backed?** 🔴 NO
- PDFs are binary files
- Filesystem storage appropriate
- May extract text that could go to notes separately

**Refactoring Needed:**
- [ ] Ensure workspace path validation
- [ ] MCP tools: Could expose specific operations like:
  - `pdf_extract_text` - Extract text from PDF
  - `pdf_fill_form` - Fill PDF form fields
  - `pdf_merge` - Merge multiple PDFs
- [ ] No database integration needed

**Priority:** MEDIUM - Useful tools, no major architecture changes

---

### 6. xlsx (Spreadsheet manipulation)
**Current State:**
- Create, edit, analyze spreadsheets
- Works with `.xlsx` files
- Supports formulas, formatting, data analysis

**Should it be database-backed?** 🔴 NO
- Spreadsheets are complex binary files
- Filesystem storage appropriate
- May extract data that could be saved to notes

**Refactoring Needed:**
- [ ] Ensure workspace path validation
- [ ] MCP tools: Could expose specific operations like:
  - `xlsx_create` - Create new spreadsheet
  - `xlsx_read` - Read data from spreadsheet
  - `xlsx_edit` - Edit existing spreadsheet
- [ ] No database integration needed

**Priority:** MEDIUM - Useful tools, no major architecture changes

---

### 7. pptx (PowerPoint manipulation)
**Current State:**
- Create, edit, analyze presentations
- Works with `.pptx` files
- Supports layouts, formatting, charts

**Should it be database-backed?** 🔴 NO
- Presentations are binary files
- Filesystem storage appropriate

**Refactoring Needed:**
- [ ] Ensure workspace path validation
- [ ] MCP tools: Could expose specific operations like:
  - `pptx_create` - Create new presentation
  - `pptx_read` - Extract text from slides
  - `pptx_edit` - Edit existing presentation
- [ ] No database integration needed

**Priority:** LOW - Useful but specialized, no major architecture changes

---

### 8. web-crawler-policy
**Current State:**
- Analyzes robots.txt and llms.txt files
- Returns analysis results (CSV, JSON, markdown)
- Optionally saves reports to `~/Documents/Agent Smith/Reports/`

**Should it be database-backed?** 🔴 NO
- Analysis tool, not persistent content
- Results are reports, not ongoing data
- Filesystem for reports is appropriate

**Refactoring Needed:**
- [ ] MCP tool: `analyze_crawler_policy` with parameters: `domain`, `options`
- [ ] Returns analysis results directly
- [ ] No database integration needed

**Priority:** LOW - Niche use case, works as-is

---

### 9. subdomain-discover
**Current State:**
- Discovers subdomains using DNS, CT logs, sitemaps
- Returns list of discovered domains (JSON)
- No persistent storage

**Should it be database-backed?** 🔴 NO
- Utility tool that returns results
- Results are transient
- No persistence needed

**Refactoring Needed:**
- [ ] MCP tool: `discover_subdomains` with parameters: `domain`, `options`
- [ ] Returns subdomain list directly
- [ ] No database integration needed

**Priority:** LOW - Niche use case, works as-is

---

### 10. skill-creator
**Current State:**
- Creates new skill scaffolding
- Initializes skill directory structure
- Development tool

**Should it be database-backed?** 🔴 NO
- Meta tool for development
- Creates files on filesystem
- No persistence needed

**Refactoring Needed:**
- [ ] MCP tool: `create_skill` with parameters: `skill_name`, `description`
- [ ] AI can create new skills programmatically
- [ ] No database integration needed

**Priority:** HIGH - Meta capability, enable AI to extend itself

---

### 11. mcp-builder
**Current State:**
- Builds MCP skill packages
- Development tool

**Should it be database-backed?** 🔴 NO
- Meta tool for packaging
- No persistence needed

**Refactoring Needed:**
- [ ] MCP tool: `build_mcp_skill` with parameters: `skill_name`
- [ ] AI can package skills
- [ ] No database integration needed

**Priority:** MEDIUM - Meta capability

---

## Summary

### Needs Database Integration (2 skills):
1. **audio-transcribe** - Save transcripts to notes table
2. **youtube-transcribe** - Save transcripts to notes table

### No Database Integration Needed (9 skills):
3. **youtube-download** - Downloads stay as files
4. **docx** - Document manipulation, files
5. **pdf** - PDF manipulation, files
6. **xlsx** - Spreadsheet manipulation, files
7. **pptx** - Presentation manipulation, files
8. **web-crawler-policy** - Analysis tool, results only
9. **subdomain-discover** - Utility tool, results only
10. **skill-creator** - Meta tool, creates files
11. **mcp-builder** - Meta tool, builds packages

### Removed Skills (2 skills):
- **list-skills** - Redundant with tool_mapper
- **folder-config** - No longer relevant with database-first architecture

### Recommended Priorities:
1. **HIGH**: audio-transcribe, youtube-transcribe (database integration)
2. **HIGH**: skill-creator, mcp-builder (meta capabilities)
3. **MEDIUM**: youtube-download, docx, pdf, xlsx (useful tools, expose as-is)
4. **LOW**: pptx, web-crawler-policy, subdomain-discover (niche/specialized)

---

## Next Steps

1. Review and approve this analysis
2. Implement database integration for transcription skills first
3. Expose high-priority tools as MCP tools
4. Add workspace path validation for all file-manipulation tools
5. Test each tool's integration with the AI agent
