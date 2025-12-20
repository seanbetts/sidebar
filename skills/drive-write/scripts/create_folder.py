#!/usr/bin/env python3
"""
Google Drive Folder Creation

Create new folders in Google Drive.
"""

import sys
import json
import argparse
from typing import Optional, Dict, Any

from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


@exponential_backoff_retry(max_retries=5)
def create_folder(
    service,
    folder_name: str,
    parent_id: Optional[str] = None,
    description: Optional[str] = None
) -> Dict[str, Any]:
    """
    Create a new folder in Google Drive.

    Args:
        service: Authenticated Google Drive service
        folder_name: Name for the new folder
        parent_id: Parent folder ID (default: root)
        description: Folder description

    Returns:
        Dictionary with created folder metadata

    Raises:
        PermanentError: For non-retryable API errors
        RetryableError: When max retries exceeded
    """
    # Build folder metadata
    folder_metadata = {
        'name': folder_name,
        'mimeType': 'application/vnd.google-apps.folder'
    }

    # Add parent folder if specified
    if parent_id:
        folder_metadata['parents'] = [parent_id]

    # Add description if provided
    if description:
        folder_metadata['description'] = description

    # Create the folder
    folder = service.files().create(
        body=folder_metadata,
        fields='id, name, mimeType, webViewLink, createdTime, parents, description',
        supportsAllDrives=True
    ).execute()

    return folder


def format_human_readable(folder_info: Dict[str, Any]) -> str:
    """
    Format folder creation result in human-readable format.

    Args:
        folder_info: Folder metadata from Drive API

    Returns:
        Formatted string for display
    """
    lines = []

    lines.append("=" * 80)
    lines.append("FOLDER CREATED SUCCESSFULLY")
    lines.append("=" * 80)
    lines.append("")

    lines.append("Folder Details:")
    lines.append(f"  Name: {folder_info.get('name', 'N/A')}")
    lines.append(f"  ID: {folder_info.get('id', 'N/A')}")
    lines.append(f"  Type: {folder_info.get('mimeType', 'N/A')}")

    if 'createdTime' in folder_info:
        lines.append(f"  Created: {folder_info['createdTime']}")

    if 'parents' in folder_info:
        lines.append(f"  Parent Folder: {folder_info['parents'][0]}")
    else:
        lines.append("  Parent Folder: root (My Drive)")

    if 'description' in folder_info:
        lines.append(f"  Description: {folder_info['description']}")

    lines.append("")

    # Link
    if 'webViewLink' in folder_info:
        lines.append("View in Drive:")
        lines.append(f"  {folder_info['webViewLink']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for create_folder script."""
    parser = argparse.ArgumentParser(
        description='Create a new folder in Google Drive',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Create folder in root
  %(prog)s "Project Files" --json

  # Create subfolder
  %(prog)s "Reports" --parent-id "1abc123" --json

  # Create with description
  %(prog)s "Archive" --description "Old project files"
        """
    )

    # Required argument
    parser.add_argument(
        'folder_name',
        help='Name for the new folder'
    )

    # Optional arguments
    parser.add_argument(
        '--parent-id',
        help='Parent folder ID (default: root)'
    )
    parser.add_argument(
        '--description',
        help='Folder description'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Get authenticated service
        service = get_drive_service()

        if not args.json:
            parent_location = f"folder {args.parent_id}" if args.parent_id else "root"
            print(f"Creating folder '{args.folder_name}' in {parent_location}...")

        # Create the folder
        folder_info = create_folder(
            service,
            folder_name=args.folder_name,
            parent_id=args.parent_id,
            description=args.description
        )

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': folder_info
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(folder_info))

        sys.exit(0)

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
                    'Verify you have write permissions to the parent folder',
                    'Check that parent folder ID exists',
                    'Ensure folder name is valid (no / or \\ characters)'
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
