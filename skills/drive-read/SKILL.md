---
name: drive-read
description: Read operations for Google Drive - list files, read metadata, download content. Use when you need to explore Drive contents or retrieve file information without modifying anything.
---

# Google Drive Read Operations

## Overview

This skill provides read-only operations for Google Drive, allowing you to list files, retrieve metadata, and download content. All operations use service account authentication configured through Doppler secrets.

## Quick Start

```bash
# List files in root folder
python /skills/drive-read/scripts/list_files.py --json

# Get file metadata
python /skills/drive-read/scripts/get_metadata.py FILE_ID --json

# Download a file
python /skills/drive-read/scripts/download_file.py FILE_ID /path/to/output.pdf
```

## Authentication

This skill uses service account authentication. The service account JSON key must be configured in Doppler as `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON`.

**Setup:**
1. Create a service account in Google Cloud Console
2. Enable Google Drive API
3. Download the JSON key file
4. Add to Doppler: `doppler secrets set GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON --value "$(cat key.json)"`
5. Share Drive files/folders with the service account email

## Scripts

### list_files.py

List files in Google Drive with filtering and pagination.

**Usage:**
```bash
python list_files.py [OPTIONS]

Options:
  --folder-id ID       List files in specific folder (default: root)
  --page-size N        Results per page (default: 100, max: 1000)
  --page-token TOKEN   Token for pagination
  --mime-type TYPE     Filter by MIME type
  --order-by FIELD     Sort by field (e.g., 'name', 'modifiedTime desc')
  --json               Output as JSON (default: human-readable)
```

**Examples:**
```bash
# List all files in root
python list_files.py --json

# List PDFs only
python list_files.py --mime-type "application/pdf" --json

# List files in specific folder, sorted by modified time
python list_files.py --folder-id "abc123" --order-by "modifiedTime desc" --json

# Pagination
python list_files.py --page-size 50 --page-token "token123" --json
```

**Output:**
```json
{
  "success": true,
  "data": {
    "files": [
      {
        "id": "1abc123",
        "name": "document.pdf",
        "mimeType": "application/pdf",
        "size": "123456",
        "modifiedTime": "2025-01-15T10:30:00.000Z",
        "owners": [{"emailAddress": "owner@example.com"}],
        "parents": ["0BxRoot"]
      }
    ],
    "nextPageToken": "token456",
    "totalFiles": 2
  }
}
```

### get_metadata.py

Retrieve complete metadata for a specific file.

**Usage:**
```bash
python get_metadata.py FILE_ID [--json]
```

**Examples:**
```bash
# Get metadata for a file
python get_metadata.py 1abc123def456 --json
```

**Output:**
```json
{
  "success": true,
  "data": {
    "id": "1abc123",
    "name": "document.pdf",
    "mimeType": "application/pdf",
    "size": "123456",
    "createdTime": "2025-01-01T12:00:00.000Z",
    "modifiedTime": "2025-01-15T10:30:00.000Z",
    "owners": [{"emailAddress": "owner@example.com", "displayName": "Owner"}],
    "parents": ["0BxRoot"],
    "webViewLink": "https://drive.google.com/file/d/1abc123/view",
    "permissions": [
      {"type": "user", "role": "owner", "emailAddress": "owner@example.com"}
    ]
  }
}
```

### download_file.py

Download file content from Google Drive.

**Usage:**
```bash
python download_file.py FILE_ID OUTPUT_PATH [--mime-type TYPE]
```

**Examples:**
```bash
# Download a binary file
python download_file.py 1abc123 /path/to/document.pdf

# Export Google Doc as PDF
python download_file.py 1abc123 /path/to/document.pdf --mime-type "application/pdf"

# Export Google Sheet as Excel
python download_file.py 1abc123 /path/to/spreadsheet.xlsx --mime-type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
```

**Supported Export Formats for Google Docs:**
- **Google Docs** → PDF, DOCX, RTF, TXT, HTML
- **Google Sheets** → XLSX, CSV, PDF, HTML
- **Google Slides** → PPTX, PDF, TXT

**Output:**
```json
{
  "success": true,
  "data": {
    "file_id": "1abc123",
    "output_path": "/path/to/document.pdf",
    "size_bytes": 123456,
    "mime_type": "application/pdf"
  }
}
```

## Common Patterns

### Find files by name pattern
```bash
# Use drive-search skill for advanced queries
# But for simple listing + filtering:
python list_files.py --json | jq '.data.files[] | select(.name | contains("report"))'
```

### Download all PDFs in a folder
```bash
# 1. List PDFs in folder
FILES=$(python list_files.py --folder-id "abc123" --mime-type "application/pdf" --json)

# 2. Download each file
echo "$FILES" | jq -r '.data.files[] | "\(.id) \(.name)"' | while read id name; do
  python download_file.py "$id" "/downloads/$name"
done
```

### Get file size and modified time
```bash
python get_metadata.py FILE_ID --json | jq '{size: .data.size, modified: .data.modifiedTime}'
```

## Error Handling

This skill implements automatic retry logic with exponential backoff for:
- Rate limit errors (429)
- Server errors (500, 503)
- Transient network issues

Permanent errors (permissions, not found) are returned immediately with detailed information:
```json
{
  "success": false,
  "error": {
    "type": "PermissionDenied",
    "message": "Insufficient permissions to access file 1abc123",
    "status_code": 403,
    "suggestions": [
      "Share the file with: service-account@project.iam.gserviceaccount.com",
      "Check that the file exists and hasn't been deleted"
    ]
  }
}
```

## Troubleshooting

### Authentication failed
- Verify `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON` is set in Doppler
- Check the JSON is valid (run `gdrive_auth.py` directly to test)
- Ensure Google Drive API is enabled in Google Cloud Console

### Permission denied errors
- Share files/folders with the service account email
- Grant at least "Viewer" permissions
- For organization files, consider domain-wide delegation

### File not found
- Verify the file ID is correct
- Check if file was deleted or is in trash
- Ensure service account has access to the file

## MIME Types Reference

Common MIME types for filtering:
- PDF: `application/pdf`
- Word: `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
- Excel: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- PowerPoint: `application/vnd.openxmlformats-officedocument.presentationml.presentation`
- Google Docs: `application/vnd.google-apps.document`
- Google Sheets: `application/vnd.google-apps.spreadsheet`
- Google Slides: `application/vnd.google-apps.presentation`
- Folders: `application/vnd.google-apps.folder`
