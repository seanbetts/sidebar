#!/usr/bin/env python3
"""
Download file content from Google Drive.

Supports both binary file downloads and Google Docs exports.

Usage:
    python download_file.py FILE_ID OUTPUT_PATH [--mime-type TYPE] [--json]

Arguments:
    FILE_ID       The Google Drive file ID
    OUTPUT_PATH   Path where file will be saved

Options:
    --mime-type TYPE    Export MIME type for Google Docs (optional)
    --json              Output as JSON

Google Docs Export Formats:
    Google Docs    → application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document
    Google Sheets  → application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, text/csv
    Google Slides  → application/vnd.openxmlformats-officedocument.presentationml.presentation, application/pdf

Examples:
    # Download binary file
    python download_file.py 1abc123 /path/to/document.pdf

    # Export Google Doc as PDF
    python download_file.py 1abc123 /path/to/doc.pdf --mime-type "application/pdf"

    # Export Google Sheet as Excel
    python download_file.py 1abc123 /path/to/sheet.xlsx --mime-type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
"""

import sys
import json
import argparse
from pathlib import Path
from typing import Optional, Dict, Any
import io

from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError
from googleapiclient.http import MediaIoBaseDownload


# Google Workspace MIME types that require export
GOOGLE_MIME_TYPES = {
    'application/vnd.google-apps.document',      # Google Docs
    'application/vnd.google-apps.spreadsheet',   # Google Sheets
    'application/vnd.google-apps.presentation',  # Google Slides
    'application/vnd.google-apps.drawing',       # Google Drawings
}


@exponential_backoff_retry(max_retries=5)
def download_file(
    service,
    file_id: str,
    output_path: str,
    mime_type: Optional[str] = None
) -> Dict[str, Any]:
    """
    Download a file from Google Drive.

    Args:
        service: Authenticated Google Drive service
        file_id: The file ID
        output_path: Path to save the file
        mime_type: Export MIME type for Google Docs (optional)

    Returns:
        dict: Download information (file_id, output_path, size, mime_type)
    """
    # Get file metadata to determine if it's a Google Doc
    file_metadata = service.files().get(
        fileId=file_id,
        fields='mimeType, name, size',
        supportsAllDrives=True
    ).execute()

    source_mime_type = file_metadata.get('mimeType')
    file_name = file_metadata.get('name')
    is_google_doc = source_mime_type in GOOGLE_MIME_TYPES

    # Ensure output directory exists
    output_path_obj = Path(output_path)
    output_path_obj.parent.mkdir(parents=True, exist_ok=True)

    if is_google_doc:
        # Export Google Docs format
        if not mime_type:
            # Auto-detect export format based on file extension
            mime_type = _guess_export_mime_type(output_path, source_mime_type)

        request = service.files().export_media(
            fileId=file_id,
            mimeType=mime_type
        )
    else:
        # Download binary file
        request = service.files().get_media(
            fileId=file_id,
            supportsAllDrives=True
        )

    # Download file
    fh = io.FileIO(output_path, 'wb')
    downloader = MediaIoBaseDownload(fh, request)

    done = False
    while not done:
        status, done = downloader.next_chunk()
        if status:
            progress = int(status.progress() * 100)
            print(f"Download progress: {progress}%", file=sys.stderr)

    fh.close()

    # Get file size
    size_bytes = output_path_obj.stat().st_size

    return {
        'file_id': file_id,
        'file_name': file_name,
        'output_path': str(output_path),
        'size_bytes': size_bytes,
        'source_mime_type': source_mime_type,
        'export_mime_type': mime_type if is_google_doc else source_mime_type
    }


def _guess_export_mime_type(output_path: str, source_mime_type: str) -> str:
    """
    Guess export MIME type based on file extension and source type.

    Args:
        output_path: Output file path
        source_mime_type: Source Google Doc MIME type

    Returns:
        str: Export MIME type
    """
    ext = Path(output_path).suffix.lower()

    # Extension to MIME type mapping
    ext_to_mime = {
        '.pdf': 'application/pdf',
        '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        '.doc': 'application/msword',
        '.txt': 'text/plain',
        '.rtf': 'application/rtf',
        '.html': 'text/html',
        '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        '.xls': 'application/vnd.ms-excel',
        '.csv': 'text/csv',
        '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        '.ppt': 'application/vnd.ms-powerpoint',
    }

    if ext in ext_to_mime:
        return ext_to_mime[ext]

    # Default exports by Google Doc type
    defaults = {
        'application/vnd.google-apps.document': 'application/pdf',
        'application/vnd.google-apps.spreadsheet': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.google-apps.presentation': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    }

    return defaults.get(source_mime_type, 'application/pdf')


def main():
    parser = argparse.ArgumentParser(
        description='Download file from Google Drive',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Download binary file
  %(prog)s 1abc123 /path/to/document.pdf

  # Export Google Doc as PDF
  %(prog)s 1abc123 /path/to/doc.pdf --mime-type "application/pdf"

  # Export Google Sheet as Excel
  %(prog)s 1abc123 /path/to/sheet.xlsx --mime-type "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

  # Export Google Sheet as CSV
  %(prog)s 1abc123 /path/to/sheet.csv --mime-type "text/csv"
        """
    )

    parser.add_argument('file_id', help='The Google Drive file ID')
    parser.add_argument('output_path', help='Path to save the downloaded file')
    parser.add_argument('--mime-type',
                        help='Export MIME type for Google Docs (auto-detected if not specified)')
    parser.add_argument('--json', action='store_true',
                        help='Output as JSON')

    args = parser.parse_args()

    try:
        # Authenticate
        service = get_drive_service()

        # Download file
        result = download_file(
            service,
            args.file_id,
            args.output_path,
            mime_type=args.mime_type
        )

        # Format output
        if args.json:
            output = {
                'success': True,
                'data': result
            }
            print(json.dumps(output, indent=2))
        else:
            size_mb = result['size_bytes'] / (1024 * 1024)
            print(f"✅ Downloaded: {result['file_name']}")
            print(f"   Saved to: {result['output_path']}")
            print(f"   Size: {size_mb:.2f} MB ({result['size_bytes']} bytes)")
            if result.get('export_mime_type') != result.get('source_mime_type'):
                print(f"   Exported from: {result['source_mime_type']}")
                print(f"   Exported as: {result['export_mime_type']}")

    except DriveAuthError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'AuthenticationError',
                'message': str(e),
                'suggestions': [
                    'Verify GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON is set in Doppler',
                    'Check that the service account JSON is valid',
                    'Ensure Google Drive API is enabled in Google Cloud Console'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except PermanentError as e:
        error_msg = str(e)
        error_type = 'PermissionError'

        # Detect specific error types
        if '404' in error_msg or 'not found' in error_msg.lower():
            error_type = 'FileNotFound'
            suggestions = [
                f'File with ID "{args.file_id}" not found',
                'Verify the file ID is correct',
                'Check if the file was deleted or is in trash'
            ]
        elif 'permission' in error_msg.lower() or '403' in error_msg:
            suggestions = [
                'Share the file with the service account',
                'Grant at least "Viewer" permissions',
                'Check that the file is not restricted'
            ]
        else:
            suggestions = ['Check the error message for details']

        error_output = {
            'success': False,
            'error': {
                'type': error_type,
                'message': error_msg,
                'file_id': args.file_id,
                'suggestions': suggestions
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except RetryableError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'RateLimitExceeded',
                'message': str(e),
                'file_id': args.file_id,
                'suggestions': [
                    'Wait a few minutes and try again',
                    'The API quota may have been exceeded'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except Exception as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'UnexpectedError',
                'message': str(e),
                'file_id': args.file_id
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
