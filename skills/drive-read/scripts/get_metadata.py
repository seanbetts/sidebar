#!/usr/bin/env python3
"""
Retrieve complete metadata for a Google Drive file.

Usage:
    python get_metadata.py FILE_ID [--json]

Arguments:
    FILE_ID    The Google Drive file ID

Options:
    --json     Output as JSON (default: human-readable)

Examples:
    python get_metadata.py 1abc123def456 --json
    python get_metadata.py 1abc123def456
"""

import sys
import json
import argparse
from typing import Dict, Any

from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


@exponential_backoff_retry(max_retries=5)
def get_file_metadata(service, file_id: str) -> Dict[str, Any]:
    """
    Retrieve complete metadata for a file.

    Args:
        service: Authenticated Google Drive service
        file_id: The file ID

    Returns:
        dict: Complete file metadata
    """
    # Fields to retrieve - comprehensive metadata
    fields = (
        "id, name, mimeType, size, createdTime, modifiedTime, "
        "owners, parents, webViewLink, webContentLink, iconLink, "
        "permissions, shared, description, starred, trashed, "
        "version, originalFilename, fileExtension, md5Checksum, "
        "capabilities, viewedByMe, viewedByMeTime"
    )

    metadata = service.files().get(
        fileId=file_id,
        fields=fields,
        supportsAllDrives=True
    ).execute()

    return metadata


def format_human_readable(metadata: Dict[str, Any]) -> str:
    """Format metadata as human-readable text."""
    output = []

    output.append(f"File: {metadata.get('name')}")
    output.append(f"ID: {metadata.get('id')}")
    output.append(f"Type: {metadata.get('mimeType')}")

    if metadata.get('description'):
        output.append(f"Description: {metadata.get('description')}")

    if metadata.get('size'):
        size_mb = int(metadata.get('size')) / (1024 * 1024)
        output.append(f"Size: {size_mb:.2f} MB ({metadata.get('size')} bytes)")

    output.append(f"Created: {metadata.get('createdTime')}")
    output.append(f"Modified: {metadata.get('modifiedTime')}")

    if metadata.get('viewedByMeTime'):
        output.append(f"Last viewed: {metadata.get('viewedByMeTime')}")

    owners = metadata.get('owners', [])
    if owners:
        owner_names = [o.get('displayName', o.get('emailAddress')) for o in owners]
        output.append(f"Owners: {', '.join(owner_names)}")

    if metadata.get('webViewLink'):
        output.append(f"View link: {metadata.get('webViewLink')}")

    if metadata.get('webContentLink'):
        output.append(f"Download link: {metadata.get('webContentLink')}")

    output.append(f"Shared: {'Yes' if metadata.get('shared') else 'No'}")
    output.append(f"Starred: {'Yes' if metadata.get('starred') else 'No'}")
    output.append(f"Trashed: {'Yes' if metadata.get('trashed') else 'No'}")

    if metadata.get('parents'):
        output.append(f"Parent folders: {', '.join(metadata.get('parents'))}")

    # Capabilities
    capabilities = metadata.get('capabilities', {})
    if capabilities:
        output.append("\nCapabilities:")
        if capabilities.get('canEdit'):
            output.append("  - Can edit")
        if capabilities.get('canComment'):
            output.append("  - Can comment")
        if capabilities.get('canShare'):
            output.append("  - Can share")
        if capabilities.get('canDownload'):
            output.append("  - Can download")

    # Permissions
    permissions = metadata.get('permissions', [])
    if permissions:
        output.append(f"\nPermissions ({len(permissions)}):")
        for perm in permissions:
            perm_type = perm.get('type', 'unknown')
            role = perm.get('role', 'unknown')
            email = perm.get('emailAddress', 'N/A')
            output.append(f"  - {role} ({perm_type}): {email}")

    return '\n'.join(output)


def main():
    parser = argparse.ArgumentParser(
        description='Retrieve metadata for a Google Drive file',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s 1abc123def456 --json
  %(prog)s 1abc123def456
        """
    )

    parser.add_argument('file_id', help='The Google Drive file ID')
    parser.add_argument('--json', action='store_true',
                        help='Output as JSON')

    args = parser.parse_args()

    try:
        # Authenticate
        service = get_drive_service()

        # Get metadata
        metadata = get_file_metadata(service, args.file_id)

        # Format output
        if args.json:
            output = {
                'success': True,
                'data': metadata
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(metadata))

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
                'Check if the file was deleted or is in trash',
                'Ensure service account has access to the file'
            ]
        else:
            suggestions = [
                'Share the file with the service account',
                'Verify the file ID is correct',
                'Check service account permissions'
            ]

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
