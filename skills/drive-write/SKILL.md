---
name: drive-write
description: Write operations for Google Drive - upload files, update content, create folders. Use when you need to add or modify files in Google Drive.
---

# Google Drive Write Skill

Write operations for Google Drive using the Google Drive API v3. This skill provides functionality to upload files, update existing content, and create folders.

## Features

- **File Upload**: Upload files with automatic MIME type detection
- **Folder Creation**: Create new folders with optional parent placement
- **File Updates**: Update file content and metadata
- **Large File Support**: Resumable uploads for files larger than 5MB
- **Flexible Metadata**: Set name, description, and parent folder during upload
- **Error Handling**: Automatic retry for transient errors

## Prerequisites

1. **Google Cloud Service Account**:
   - Service account with Drive API enabled
   - JSON credentials stored in Doppler as `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON`
   - Write permissions on target folders

2. **Environment Setup**:
   - Python 3.8+
   - Google API Python dependencies installed
   - Doppler CLI configured

## Scripts

### upload_file.py

Upload a file to Google Drive.

**Usage:**
```bash
python /skills/drive-write/scripts/upload_file.py FILE_PATH [OPTIONS]
```

**Required Arguments:**
- `FILE_PATH` - Path to the local file to upload

**Options:**
- `--name NAME` - Name for the file in Drive (default: original filename)
- `--parent-id ID` - Parent folder ID to upload into (default: root)
- `--mime-type TYPE` - MIME type (default: auto-detected from file extension)
- `--description TEXT` - File description
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Upload a file to root
python upload_file.py /path/to/document.pdf --json

# Upload with custom name to specific folder
python upload_file.py /path/to/file.txt --name "Report 2025" --parent-id "1abc123"

# Upload with description
python upload_file.py /path/to/image.jpg --description "Project screenshot" --json

# Upload with specific MIME type
python upload_file.py /path/to/data.csv --mime-type "text/csv"
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "id": "1abc...",
    "name": "document.pdf",
    "mimeType": "application/pdf",
    "size": "524288",
    "webViewLink": "https://drive.google.com/file/d/1abc.../view",
    "createdTime": "2025-12-20T10:30:00.000Z"
  }
}
```

**Features:**
- Automatic MIME type detection using Python's `mimetypes` module
- Resumable uploads for large files (>5MB)
- Progress indication for large uploads
- Returns complete file metadata including shareable link

### create_folder.py

Create a new folder in Google Drive.

**Usage:**
```bash
python /skills/drive-write/scripts/create_folder.py FOLDER_NAME [OPTIONS]
```

**Required Arguments:**
- `FOLDER_NAME` - Name for the new folder

**Options:**
- `--parent-id ID` - Parent folder ID (default: root)
- `--description TEXT` - Folder description
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Create folder in root
python create_folder.py "Project Files" --json

# Create subfolder
python create_folder.py "Reports" --parent-id "1abc123" --json

# Create with description
python create_folder.py "Archive" --description "Old project files"
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "id": "1xyz...",
    "name": "Project Files",
    "mimeType": "application/vnd.google-apps.folder",
    "webViewLink": "https://drive.google.com/drive/folders/1xyz...",
    "createdTime": "2025-12-20T10:30:00.000Z"
  }
}
```

### update_file.py

Update an existing file's content and/or metadata.

**Usage:**
```bash
python /skills/drive-write/scripts/update_file.py FILE_ID [OPTIONS]
```

**Required Arguments:**
- `FILE_ID` - ID of the file to update

**Options:**
- `--content-path PATH` - Path to new content file (updates file content)
- `--name NAME` - New name for the file (updates metadata)
- `--description TEXT` - New description (updates metadata)
- `--json` - Output JSON format (default: human-readable)

**Examples:**
```bash
# Update file content
python update_file.py "1abc123" --content-path /path/to/new-version.pdf --json

# Rename file
python update_file.py "1abc123" --name "Updated Report 2025" --json

# Update content and metadata
python update_file.py "1abc123" --content-path /path/to/file.txt --name "Final Version" --description "Completed"

# Update only description
python update_file.py "1abc123" --description "Updated on 2025-12-20"
```

**Response Format (JSON):**
```json
{
  "success": true,
  "data": {
    "id": "1abc...",
    "name": "Updated Report 2025",
    "mimeType": "application/pdf",
    "size": "624288",
    "webViewLink": "https://drive.google.com/file/d/1abc.../view",
    "modifiedTime": "2025-12-20T10:35:00.000Z"
  }
}
```

## MIME Type Reference

Common MIME types for uploads:

**Documents:**
- `application/pdf` - PDF files (.pdf)
- `text/plain` - Text files (.txt)
- `application/msword` - Word (.doc)
- `application/vnd.openxmlformats-officedocument.wordprocessingml.document` - Word (.docx)

**Spreadsheets:**
- `text/csv` - CSV files (.csv)
- `application/vnd.ms-excel` - Excel (.xls)
- `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` - Excel (.xlsx)

**Images:**
- `image/jpeg` - JPEG images (.jpg, .jpeg)
- `image/png` - PNG images (.png)
- `image/gif` - GIF images (.gif)

**Other:**
- `application/zip` - ZIP archives (.zip)
- `application/json` - JSON files (.json)
- `video/mp4` - MP4 videos (.mp4)

**Note:** MIME type is auto-detected if not specified.

## File Size Limits

- **Standard Upload**: Files up to 5MB use simple upload
- **Resumable Upload**: Files over 5MB use resumable upload
- **Maximum Size**: 5TB per file (Google Drive limit)

## Error Handling

- **Rate Limits**: Automatic exponential backoff retry (429, 503 errors)
- **Authentication Errors**: Clear error messages with setup instructions
- **Permission Errors**: Returns descriptive error when write access is denied
- **File Not Found**: Returns error if updating non-existent file
- **Quota Exceeded**: Returns error if storage quota is full

## Permissions

The service account must have write permissions:
- **Editor** or **Content Manager** role on target folders
- Share folders with service account email: `name@project-id.iam.gserviceaccount.com`
- **Owner** role required to share or change permissions (use drive-manage skill)

## Best Practices

1. **File Organization**: Use folders to organize uploads
2. **Naming**: Use descriptive names to make files searchable
3. **Descriptions**: Add descriptions for important files
4. **Batch Operations**: Upload multiple files efficiently using the script in a loop
5. **Error Handling**: Check response status before proceeding
6. **Large Files**: Use resumable uploads for reliability

## Related Skills

- **drive-read**: List files, get metadata, download content
- **drive-search**: Find files using advanced queries
- **drive-manage**: Move, rename, delete files, manage permissions

## Authentication

Uses service account authentication via `GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON` environment variable (stored in Doppler).

## Troubleshooting

**Permission denied:**
- Verify service account has Editor/Content Manager access to folder
- Share target folder with service account email
- Check that Drive API is enabled in Google Cloud Console

**File already exists:**
- Google Drive allows duplicate names (different IDs)
- Use drive-search to find existing files before uploading
- Consider using update_file.py to replace content

**Upload fails for large files:**
- Check internet connection stability
- Resumable uploads will automatically retry
- Monitor Google Cloud Console for quota limits

**MIME type incorrect:**
- Specify `--mime-type` explicitly if auto-detection fails
- Check file extension matches actual content
- Use `file` command on Unix to verify file type
