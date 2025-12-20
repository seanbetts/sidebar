#!/usr/bin/env python3
"""
Google Drive File Update

Update existing files' content and/or metadata in Google Drive.
"""

import sys
import json
import argparse
import os
from typing import Optional, Dict, Any

from googleapiclient.http import MediaFileUpload
from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


@exponential_backoff_retry(max_retries=5)
def update_file(
    service,
    file_id: str,
    content_path: Optional[str] = None,
    name: Optional[str] = None,
    description: Optional[str] = None
) -> Dict[str, Any]:
    """
    Update an existing file's content and/or metadata.

    Args:
        service: Authenticated Google Drive service
        file_id: ID of the file to update
        content_path: Path to new content file (updates content)
        name: New name for the file (updates metadata)
        description: New description (updates metadata)

    Returns:
        Dictionary with updated file metadata

    Raises:
        PermanentError: For non-retryable API errors
        RetryableError: When max retries exceeded
        FileNotFoundError: If content_path doesn't exist
        ValueError: If no updates are specified
    """
    # Verify at least one update is specified
    if not content_path and not name and description is None:
        raise ValueError("Must specify at least one of: content_path, name, or description")

    # Verify content file exists if specified
    if content_path and not os.path.exists(content_path):
        raise FileNotFoundError(f"Content file not found: {content_path}")

    # Build metadata update
    file_metadata = {}

    if name:
        file_metadata['name'] = name

    if description is not None:  # Allow empty string to clear description
        file_metadata['description'] = description

    # Prepare media upload if updating content
    media = None
    if content_path:
        # Get the existing file's MIME type
        existing_file = service.files().get(
            fileId=file_id,
            fields='mimeType',
            supportsAllDrives=True
        ).execute()

        mime_type = existing_file.get('mimeType', 'application/octet-stream')

        media = MediaFileUpload(
            content_path,
            mimetype=mime_type,
            resumable=True
        )

    # Update the file
    file = service.files().update(
        fileId=file_id,
        body=file_metadata if file_metadata else None,
        media_body=media,
        fields='id, name, mimeType, size, webViewLink, modifiedTime, description',
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


def format_human_readable(file_info: Dict[str, Any], updates: Dict[str, Any]) -> str:
    """
    Format update result in human-readable format.

    Args:
        file_info: File metadata from Drive API
        updates: Dictionary of what was updated

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("FILE UPDATED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    # What was updated
    lines.append("Updates Applied:")
    if updates.get('content_updated'):
        lines.append(f"  ✓ Content updated from: {updates['content_path']}")
    if updates.get('name_updated'):
        lines.append(f"  ✓ Name changed to: {updates['new_name']}")
    if updates.get('description_updated'):
        desc = updates['new_description']
        if desc:
            lines.append(f"  ✓ Description updated: {desc}")
        else:
            lines.append("  ✓ Description cleared")
    lines.append("")

    # Current file info
    lines.append("Current File Details:")
    lines.append(f"  Name: {file_info.get('name', 'N/A')}")
    lines.append(f"  ID: {file_info.get('id', 'N/A')}")
    lines.append(f"  Type: {file_info.get('mimeType', 'N/A')}")

    if 'size' in file_info:
        drive_size = int(file_info['size'])
        lines.append(f"  Size: {format_file_size(drive_size)}")

    if 'modifiedTime' in file_info:
        lines.append(f"  Last Modified: {file_info['modifiedTime']}")

    if 'description' in file_info and file_info['description']:
        lines.append(f"  Description: {file_info['description']}")

    lines.append("")

    # Link
    if 'webViewLink' in file_info:
        lines.append("View in Drive:")
        lines.append(f"  {file_info['webViewLink']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for update_file script."""
    parser = argparse.ArgumentParser(
        description='Update an existing file in Google Drive',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Update file content
  %(prog)s "1abc123" --content-path /path/to/new-version.pdf --json

  # Rename file
  %(prog)s "1abc123" --name "Updated Report 2025" --json

  # Update content and metadata
  %(prog)s "1abc123" --content-path /path/to/file.txt --name "Final Version" --description "Completed"

  # Update only description
  %(prog)s "1abc123" --description "Updated on 2025-12-20"
        """
    )

    # Required argument
    parser.add_argument(
        'file_id',
        help='ID of the file to update'
    )

    # Optional arguments
    parser.add_argument(
        '--content-path',
        help='Path to new content file (updates file content)'
    )
    parser.add_argument(
        '--name',
        help='New name for the file (updates metadata)'
    )
    parser.add_argument(
        '--description',
        help='New description (updates metadata)'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Verify at least one update is specified
        if not args.content_path and not args.name and args.description is None:
            parser.error("Must specify at least one of: --content-path, --name, or --description")

        # Verify content file exists if specified
        if args.content_path and not os.path.exists(args.content_path):
            raise FileNotFoundError(f"Content file not found: {args.content_path}")

        # Get authenticated service
        service = get_drive_service()

        if not args.json:
            updates = []
            if args.content_path:
                updates.append(f"content from {args.content_path}")
            if args.name:
                updates.append(f"name to '{args.name}'")
            if args.description is not None:
                updates.append("description")
            print(f"Updating file {args.file_id}: {', '.join(updates)}...")

        # Update the file
        file_info = update_file(
            service,
            file_id=args.file_id,
            content_path=args.content_path,
            name=args.name,
            description=args.description
        )

        # Track what was updated for display
        updates = {
            'content_updated': bool(args.content_path),
            'content_path': args.content_path,
            'name_updated': bool(args.name),
            'new_name': args.name,
            'description_updated': args.description is not None,
            'new_description': args.description
        }

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': file_info,
                'updates': updates
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(file_info, updates))

        sys.exit(0)

    except FileNotFoundError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'FileNotFoundError',
                'message': str(e),
                'suggestions': [
                    'Verify the content file path is correct',
                    'Check that the file exists',
                    'Use absolute path if relative path is not working'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'ValueError',
                'message': str(e),
                'suggestions': [
                    'Specify at least one update: --content-path, --name, or --description',
                    'Check the command usage with --help'
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
                    'Verify the file ID exists',
                    'Check that you have write permissions',
                    'Ensure the file is not read-only'
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
                    'Check Google Cloud Console for quota limits'
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
