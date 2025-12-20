#!/usr/bin/env python3
"""
Google Drive File Upload

Upload files to Google Drive with automatic MIME type detection.
Supports both simple and resumable uploads for large files.
"""

import sys
import json
import argparse
import os
import mimetypes
from typing import Optional, Dict, Any

from googleapiclient.http import MediaFileUpload
from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


# Threshold for resumable upload (5MB)
RESUMABLE_THRESHOLD = 5 * 1024 * 1024


def detect_mime_type(file_path: str) -> str:
    """
    Auto-detect MIME type from file extension.

    Args:
        file_path: Path to the file

    Returns:
        MIME type string (defaults to 'application/octet-stream')
    """
    mime_type, _ = mimetypes.guess_type(file_path)
    return mime_type or 'application/octet-stream'


@exponential_backoff_retry(max_retries=5)
def upload_file(
    service,
    file_path: str,
    name: Optional[str] = None,
    parent_id: Optional[str] = None,
    mime_type: Optional[str] = None,
    description: Optional[str] = None
) -> Dict[str, Any]:
    """
    Upload a file to Google Drive.

    Args:
        service: Authenticated Google Drive service
        file_path: Path to the local file to upload
        name: Name for the file in Drive (default: original filename)
        parent_id: Parent folder ID (default: root)
        mime_type: MIME type (default: auto-detected)
        description: File description

    Returns:
        Dictionary with uploaded file metadata

    Raises:
        PermanentError: For non-retryable API errors
        RetryableError: When max retries exceeded
        FileNotFoundError: If file_path doesn't exist
    """
    # Verify file exists
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    # Get file size
    file_size = os.path.getsize(file_path)

    # Use original filename if name not provided
    if name is None:
        name = os.path.basename(file_path)

    # Auto-detect MIME type if not provided
    if mime_type is None:
        mime_type = detect_mime_type(file_path)

    # Build file metadata
    file_metadata = {
        'name': name,
        'mimeType': mime_type
    }

    # Add parent folder if specified
    if parent_id:
        file_metadata['parents'] = [parent_id]

    # Add description if provided
    if description:
        file_metadata['description'] = description

    # Determine upload type based on file size
    if file_size >= RESUMABLE_THRESHOLD:
        # Use resumable upload for large files
        media = MediaFileUpload(
            file_path,
            mimetype=mime_type,
            resumable=True,
            chunksize=1024 * 1024  # 1MB chunks
        )
    else:
        # Use simple upload for small files
        media = MediaFileUpload(
            file_path,
            mimetype=mime_type,
            resumable=False
        )

    # Upload the file
    file = service.files().create(
        body=file_metadata,
        media_body=media,
        fields='id, name, mimeType, size, webViewLink, createdTime, parents',
        supportsAllDrives=True
    ).execute()

    return file


def format_file_size(size_bytes: int) -> str:
    """
    Format file size in human-readable format.

    Args:
        size_bytes: File size in bytes

    Returns:
        Formatted size string
    """
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.2f} KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.2f} MB"
    else:
        return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


def format_human_readable(file_info: Dict[str, Any], local_path: str) -> str:
    """
    Format upload result in human-readable format.

    Args:
        file_info: File metadata from Drive API
        local_path: Original local file path

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("FILE UPLOADED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    # Local file info
    lines.append("Local File:")
    lines.append(f"  Path: {local_path}")
    local_size = os.path.getsize(local_path)
    lines.append(f"  Size: {format_file_size(local_size)}")
    lines.append("")

    # Drive file info
    lines.append("Google Drive:")
    lines.append(f"  Name: {file_info.get('name', 'N/A')}")
    lines.append(f"  ID: {file_info.get('id', 'N/A')}")
    lines.append(f"  Type: {file_info.get('mimeType', 'N/A')}")

    if 'size' in file_info:
        drive_size = int(file_info['size'])
        lines.append(f"  Size: {format_file_size(drive_size)}")

    if 'createdTime' in file_info:
        lines.append(f"  Created: {file_info['createdTime']}")

    if 'parents' in file_info:
        lines.append(f"  Parent Folder: {file_info['parents'][0]}")

    lines.append("")

    # Link
    if 'webViewLink' in file_info:
        lines.append("View in Drive:")
        lines.append(f"  {file_info['webViewLink']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for upload_file script."""
    parser = argparse.ArgumentParser(
        description='Upload a file to Google Drive',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Upload a file to root
  %(prog)s /path/to/document.pdf --json

  # Upload with custom name to specific folder
  %(prog)s /path/to/file.txt --name "Report 2025" --parent-id "1abc123"

  # Upload with description
  %(prog)s /path/to/image.jpg --description "Project screenshot"
        """
    )

    # Required argument
    parser.add_argument(
        'file_path',
        help='Path to the local file to upload'
    )

    # Optional arguments
    parser.add_argument(
        '--name',
        help='Name for the file in Drive (default: original filename)'
    )
    parser.add_argument(
        '--parent-id',
        help='Parent folder ID to upload into (default: root)'
    )
    parser.add_argument(
        '--mime-type',
        help='MIME type (default: auto-detected from file extension)'
    )
    parser.add_argument(
        '--description',
        help='File description'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Verify file exists before authenticating
        if not os.path.exists(args.file_path):
            raise FileNotFoundError(f"File not found: {args.file_path}")

        # Get file size for display
        file_size = os.path.getsize(args.file_path)

        # Show upload type
        if not args.json:
            upload_type = "resumable" if file_size >= RESUMABLE_THRESHOLD else "simple"
            print(f"Uploading {format_file_size(file_size)} using {upload_type} upload...")

        # Get authenticated service
        service = get_drive_service()

        # Upload the file
        file_info = upload_file(
            service,
            file_path=args.file_path,
            name=args.name,
            parent_id=args.parent_id,
            mime_type=args.mime_type,
            description=args.description
        )

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': file_info
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(file_info, args.file_path))

        sys.exit(0)

    except FileNotFoundError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileNotFoundError',
                'message': str(e),
                'suggestions': [
                    'Verify the file path is correct',
                    'Check that the file exists',
                    'Use absolute path if relative path is not working'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except DriveAuthError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'AuthenticationError',
                'message': str(e),
                'suggestions': [
                    'Ensure GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON is set in Doppler',
                    'Verify service account has Drive API enabled',
                    'Check that JSON credentials are valid'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except PermanentError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'PermanentError',
                'message': str(e),
                'suggestions': [
                    'Verify you have write permissions to the target folder',
                    'Check that parent folder ID exists',
                    'Ensure storage quota is not exceeded'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except RetryableError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'RetryableError',
                'message': str(e),
                'suggestions': [
                    'Rate limit exceeded - wait a few moments and try again',
                    'Check Google Cloud Console for quota limits',
                    'Try uploading smaller files or fewer files at once'
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
                'message': f'Unexpected error: {str(e)}',
                'suggestions': [
                    'Check the error message for details',
                    'Verify all parameters are correct',
                    'Try the operation again'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
