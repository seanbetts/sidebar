---
name: drive-search
description: Advanced search for Google Drive - query by mimeType, name, parents, modified time, and more. Use when you need to find specific files using complex criteria.
---

# Google Drive Search Skill

Advanced search operations for Google Drive using the Google Drive API v3. This skill provides powerful query capabilities to find files using multiple filter criteria.

## Features

- **Advanced Filtering**: Search by name, MIME type, modification time, owner, and more
- **Flexible Queries**: Combine multiple search criteria
- **Full-Text Search**: Search within file names and content
- **Pagination**: Handle large result sets efficiently
- **Sorting**: Order results by various fields

## Prerequisites

1. **Google Cloud Service Account**:
   - Service account with Drive API enabled
   - JSON credentials stored in Doppler as `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON`
   - Files/folders shared with service account email

2. **Environment Setup**:
   - Python 3.8+
   - Google API Python dependencies installed
   - Doppler CLI configured

## Scripts

### search_files.py

Advanced file search with multiple filter options.

**Usage:**
```bash
python /skills/drive-search/scripts/search_files.py [OPTIONS]
```

**Options:**
- `--name-contains TEXT` - Search for files with names containing this text
- `--mime-type TYPE` - Filter by MIME type (e.g., application/pdf)
- `--modified-after DATE` - Files modified after this date (ISO 8601 format)
- `--modified-before DATE` - Files modified before this date
- `--owner EMAIL` - Filter by owner email address
- `--in-folder ID` - Search within a specific folder
- `--starred` - Only return starred files
- `--page-size N` - Results per page (default: 100, max: 1000)
- `--page-token TOKEN` - Pagination token for next page
- `--order-by FIELD` - Sort results (e.g., "modifiedTime desc")
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Search for PDF files containing "invoice"
python search_files.py --name-contains "invoice" --mime-type "application/pdf" --json

# Find files modified in the last week
python search_files.py --modified-after "2025-12-13T00:00:00Z" --order-by "modifiedTime desc"

# Search within a specific folder
python search_files.py --in-folder "1a2b3c4d5e" --name-contains "report"

# Find starred spreadsheets
python search_files.py --starred --mime-type "application/vnd.google-apps.spreadsheet"

# Files owned by specific user
python search_files.py --owner "user@example.com"
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "files": [
      {
        "id": "1abc...",
        "name": "Invoice_2025.pdf",
        "mimeType": "application/pdf",
        "size": "524288",
        "modifiedTime": "2025-12-15T10:30:00.000Z",
        "createdTime": "2025-12-01T09:00:00.000Z",
        "owners": [{"emailAddress": "user@example.com", "displayName": "User"}],
        "webViewLink": "https://drive.google.com/file/d/1abc.../view"
      }
    ],
    "nextPageToken": "token...",
    "totalFiles": 1
  }
}
```

## Common MIME Types

- **Documents**:
  - `application/vnd.google-apps.document` - Google Docs
  - `application/pdf` - PDF files
  - `application/msword` - Word documents (.doc)
  - `application/vnd.openxmlformats-officedocument.wordprocessingml.document` - Word (.docx)

- **Spreadsheets**:
  - `application/vnd.google-apps.spreadsheet` - Google Sheets
  - `application/vnd.ms-excel` - Excel (.xls)
  - `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` - Excel (.xlsx)

- **Presentations**:
  - `application/vnd.google-apps.presentation` - Google Slides
  - `application/vnd.ms-powerpoint` - PowerPoint (.ppt)
  - `application/vnd.openxmlformats-officedocument.presentationml.presentation` - PowerPoint (.pptx)

- **Other**:
  - `application/vnd.google-apps.folder` - Folders
  - `image/jpeg`, `image/png` - Images
  - `video/mp4` - Videos
  - `text/plain` - Text files

## Date Format

Use ISO 8601 format for dates: `YYYY-MM-DDTHH:MM:SS.sssZ`

Examples:
- `2025-12-15T00:00:00Z` - Start of Dec 15, 2025 (UTC)
- `2025-12-15T23:59:59Z` - End of Dec 15, 2025 (UTC)
- `2025-01-01T00:00:00Z` - Start of 2025

## Query Syntax

The search uses Google Drive's query syntax internally. Multiple filters are combined with AND logic:

```
name contains 'invoice' and mimeType = 'application/pdf' and modifiedTime > '2025-12-01T00:00:00Z'
```

## Error Handling

- **Rate Limits**: Automatic exponential backoff retry (429, 503 errors)
- **Authentication Errors**: Clear error messages with setup instructions
- **Permission Errors**: Returns descriptive error when files are inaccessible
- **Invalid Parameters**: Validates inputs before making API calls

## Pagination

Search results are paginated:
1. Set `--page-size` to control results per page (max 1000)
2. Check response for `nextPageToken`
3. Use `--page-token` with the token to get next page
4. Continue until `nextPageToken` is null

## Performance Tips

- Use specific filters to reduce result size
- Limit `page-size` for faster initial results
- Sort by relevant fields to get most important results first
- Search within specific folders when possible

## Related Skills

- **drive-read**: List files, get metadata, download content
- **drive-write**: Upload and update files
- **drive-manage**: Move, rename, delete files, manage permissions

## Authentication

Uses service account authentication via `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON` environment variable (stored in Doppler).

## Troubleshooting

**No results found:**
- Verify service account has access to the files
- Check if files are in shared drives (requires proper permissions)
- Ensure date formats are correct (ISO 8601)
- Try broader search criteria

**Permission denied:**
- Share files/folders with service account email: `name@project-id.iam.gserviceaccount.com`
- Verify service account has Drive API enabled
- Check that files are not in restricted shared drives

**Rate limit errors:**
- Automatic retry with exponential backoff handles most cases
- If persistent, reduce request frequency
- Consider using pagination to spread requests over time
