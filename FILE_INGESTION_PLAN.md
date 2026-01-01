Goal

Single ingestion pipeline that, for every uploaded file, produces:
	•	A canonical viewer asset (PDF or original image)
	•	A standardised PDF derivative for UI viewing (when applicable)
	•	A structured ai.md companion file for your AI agent
	•	Optional thumbnails and machine-friendly extractions

High-level architecture

Svelte frontend
	•	Upload UI
	•	Universal viewer UI that selects the best available derivative (PDF or image) and falls back gracefully
	•	Processing state indicators (queued, processing, ready, failed)

FastAPI backend
	•	Upload endpoints and authentication
	•	Storage abstraction (local filesystem, S3-compatible, Google Drive, etc.)
	•	Metadata persistence and indexing (Postgres)
	•	Dispatches file-processing jobs to a worker queue

Worker (separate process/container)
	•	Converts Office formats to PDF
	•	Extracts text, structure, tables, and slide content
	•	Generates ai.md
	•	Generates thumbnails
	•	Writes derivatives back to storage and updates database state

Storage model

Use object-storage semantics even if implemented on local disk.

Storage keys

Namespace every file by a stable file_id (UUID), prefixed by user_id:

{user_id}/files/{file_id}/derivatives/viewer.pdf
{user_id}/files/{file_id}/derivatives/thumb.png
{user_id}/files/{file_id}/ai/ai.md

Rationale
	•	Easy to add new derivatives later
	•	Clean cache invalidation via versioning
	•	Auditable, append-friendly storage

Database schema

files
	•	id (uuid, pk)
	•	owner_user_id (uuid)
	•	filename_original (text)
	•	mime_original (text)
	•	size_bytes (bigint)
	•	sha256 (text)
	•	created_at (timestamp)
	•	deleted_at (timestamp, nullable)

file_derivatives
	•	id (uuid, pk)
	•	file_id (uuid, fk)
	•	kind (enum: viewer_pdf, thumb_png, ai_md, text_plain, etc.)
	•	storage_key (text)
	•	mime (text)
	•	size_bytes (bigint)
	•	sha256 (text, nullable)
	•	created_at (timestamp)

file_processing_jobs
	•	id (uuid, pk)
	•	file_id (uuid, fk)
	•	status (enum: queued, processing, ready, failed)
	•	stage (text, nullable)
	•	error (text, nullable)
	•	attempts (int)
	•	started_at (timestamp, nullable)
	•	finished_at (timestamp, nullable)
	•	updated_at (timestamp)

API endpoints

Upload and metadata

POST /api/ingestion
	•	Multipart upload
	•	Creates DB record, enqueues processing job
	•	Returns { file_id }

GET /api/ingestion/{file_id}/meta
	•	Returns base metadata, processing status, available derivatives
	•	Includes recommended viewer (for example viewer_pdf if present)

File streaming

GET /api/ingestion/{file_id}/content?kind=viewer_pdf|thumb_png|ai_md|…
	•	Streams bytes
	•	Sets correct Content-Type
	•	Uses Content-Disposition: inline for viewable assets
	•	Optionally supports range requests for PDFs

Processing control

DELETE /api/ingestion/{file_id}
	•	Soft-deletes metadata
	•	Optionally schedules storage cleanup after a retention window
	•	Disallowed while processing

Processing status controls

POST /api/ingestion/{file_id}/pause
	•	Pauses an in-flight job

POST /api/ingestion/{file_id}/resume
	•	Resumes a paused job

POST /api/ingestion/{file_id}/cancel
	•	Cancels processing and deletes any staged artifacts

Worker pipeline

Treat processing as a deterministic state machine per file.

Stage 0: Validate and classify
	•	Validate extension and MIME against allowlist
	•	Compute sha256
	•	Optional deduplication per user
	•	Enforce maximum file size (recommend 100 MB)

Stage 1: Generate viewer derivative

Rules:
	•	PDF input: reuse as viewer.pdf (canonical stored asset)
	•	Images: no PDF conversion; store canonical image plus thumbnail
	•	DOCX/XLSX/PPTX: convert to viewer.pdf via LibreOffice headless
	•	Spreadsheets: prefer viewer_json (no PDF conversion)
	•	Text and JSON: store text_original derivative for viewing

Implementation notes:
	•	Install fonts in worker container for stable layout
	•	Enforce per-file timeouts and memory limits
	•	Process in staging; only persist to storage on final success

Stage 2: Extract content for AI

Prefer extracting from the source format rather than from the PDF.
	•	PDF: extract text per page with page numbers
	•	DOCX: headings, paragraphs, lists, tables, links
	•	XLSX: workbook structure, per-sheet tables, headers, row counts
	•	PPTX: slide titles, bullets, speaker notes, ordering

Stage 3: Build ai.md

The canonical agent-facing representation.

Front matter example:

file_id: <uuid>
source_filename: <original>
source_mime: <mime>
created_at: <iso>
sha256: <sha>
extraction_version: vX.Y
derivatives:
  viewer_pdf: true
  thumb_png: true

Body conventions:
	•	PDFs: ## Page 1, ## Page 2
	•	PPTX: ## Slide 1, ## Slide 2
	•	XLSX: ## Sheet: Sales Q4

Tables:
	•	Short natural-language summary
	•	Optional markdown preview
	•	Canonical machine block:
	•	Embedded csv fenced block, or

Images and figures:
	•	Include extracted alt text if present
	•	Add references back to viewer PDF when possible

Stage 4: Thumbnails
	•	Render first page of viewer.pdf to thumb.png
	•	For images, generate resized thumbnail
	•	Requires Poppler (`pdftoppm`) in the worker/container (macOS: `brew install poppler`)

Stage 5: Persist and finalise
	•	Write derivatives to storage (R2)
	•	Upsert derivative rows (single transaction)
	•	Mark job ready or failed with error details
	•	On failure, delete staged artifacts immediately

Viewer strategy (Svelte)

Derivative-first decision order:
	1.	If viewer_pdf exists, render via PDF viewer
	2.	Else if image, render image viewer
	3.	Else show “No preview available” with download option

UniversalViewer.svelte:
	•	Fetches /meta
	•	Selects best derivative
	•	Streams content via /content

Sharing with the AI agent

Per file, optionally store external attachment IDs (if using a Files API):
	•	ai_md as text/plain
	•	viewer.pdf as a document attachment

Policy:
	•	Default to sharing ai.md for Q&A, summarisation, and extraction
	•	Attach viewer.pdf when layout, charts, citations, or page references matter

Operations and safety
	•	Worker runs in a resource-limited container
	•	Strict allowlist of file types
	•	Timeouts per conversion stage
	•	Structured logging with file_id correlation
	•	Retention policies for internal and external storage
	•	Single in-flight job per file_id (lock/lease)
	•	Atomic finalization: no R2/DB writes until pipeline success
	•	No original file retention by default
	•	Queue uses PostgreSQL (no external queue)
	•	Worker heartbeat + lease expiry for crash recovery
	•	Retry with backoff per stage and overall attempt cap
	•	User-facing error codes and messages per failure type

Ingestion entry points

	•	File sidebar upload (+ file button): direct file ingestion.
	•	Chat attachment upload: runs the same ingestion pipeline.
	•	Chat attachments are not passed to the assistant until processing status is ready.
	•	When ready, attach canonical viewer asset and ai.md as appropriate.

Extensibility checklist

To add a new file type:
	1.	Add classifier rule (extension + MIME)
	2.	Decide viewing derivative (prefer PDF)
	3.	Implement extractor to intermediate representation
	4.	Render into ai.md
	5.	Add tests with golden outputs

UI status and progress

	•	Show a pipeline progress indicator with stages and timestamps
	•	Expose current stage (queued, processing, converting, extracting, ai_md, thumb, finalizing)
	•	Provide pause/resume/cancel controls during processing
	•	Disable delete until processing status is ready
	•	Status labels should match worker stages exactly: validating, converting, extracting, ai_md, thumb, finalizing

Queue and worker details

	•	PostgreSQL-backed queue using file_processing_jobs table
	•	Worker claims jobs via lease (e.g., status=processing, worker_id, lease_expires_at)
	•	Heartbeat updates lease_expires_at at a fixed interval (e.g., every 15s)
	•	If lease expires, job can be re-claimed by another worker
	•	Paused jobs are not claimed; canceled jobs trigger cleanup and are terminal

Retry and backoff

	•	Retry policy per stage with exponential backoff (e.g., 3 attempts, 2s → 4s → 8s)
	•	Reset stage attempts when moving to next stage
	•	After max attempts, mark job failed and delete staged artifacts
	•	Retryable errors vs non-retryable (e.g., unsupported file type is terminal)
	•	User-triggered retries are disabled; re-upload to try again

Error codes and user messaging

	•	Define stable error codes (e.g., FILE_TOO_LARGE, UNSUPPORTED_TYPE, CONVERSION_TIMEOUT)
	•	Store last_error_code + last_error_message on job record
	•	Map codes to friendly UI messages (e.g., “We couldn’t process this file. Try a PDF.”)
	•	Surface retry action when error is retryable

Implementation status

	•	[x] Ingestion metadata tables + RLS policies
	•	[x] Upload endpoint + job enqueue
	•	[x] /meta response with derivatives + recommended viewer
	•	[x] Content streaming with PDF range support
	•	[x] Pause/resume/cancel/delete controls
	•	[x] Worker leasing + retry/backoff for stalled jobs
	•	[x] PDF/image/audio/text/spreadsheet ingestion paths
	•	[x] JSON viewer for spreadsheets
	•	[x] ai.md generation with front matter
	•	[x] Thumbnail generation for PDFs/images
	•	[x] UI viewer + status polling + markdown toggle
	•	[x] Heartbeat/lease refresh during long-running work
	•	[x] Atomic storage finalization (no partial writes on failure)
	•	[x] Real work mapped to stage labels (validating, converting, extracting, ai_md, thumb, finalizing)
	•	[x] Explicit allowlist validation in Stage 0
	•	[x] Storage cleanup for failed staged writes
	•	[x] Dependency pinning constraints file (`backend/api/constraints.txt`)
