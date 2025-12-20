#!/usr/bin/env python3
"""
List files in Google Drive with filtering and pagination.

Usage:
    python list_files.py [OPTIONS]

Options:
    --folder-id ID       List files in specific folder (default: root)
    --page-size N        Results per page (default: 100, max: 1000)
    --page-token TOKEN   Token for pagination
    --mime-type TYPE     Filter by MIME type
    --order-by FIELD     Sort by field (e.g., 'name', 'modifiedTime desc')
    --json               Output as JSON (default: human-readable)

Examples:
    python list_files.py --json
    python list_files.py --folder-id "abc123" --mime-type "application/pdf" --json
    python list_files.py --order-by "modifiedTime desc" --page-size 50 --json
"""

import sys
import json
import argparse
from typing import Optional, Dict, Any

from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


@exponential_backoff_retry(max_retries=5)
def list_files(
    service,
    folder_id: Optional[str] = None,
    page_size: int = 100,
    page_token: Optional[str] = None,
    mime_type: Optional[str] = None,
    order_by: Optional[str] = None
) -> Dict[str, Any]:
    """
    List files in Google Drive with optional filtering.

    Args:
        service: Authenticated Google Drive service
        folder_id: Parent folder ID (default: root)
        page_size: Number of results per page (max: 1000)
        page_token: Token for pagination
        mime_type: Filter by MIME type
        order_by: Sort order (e.g., 'name', 'modifiedTime desc')

    Returns:
        dict: API response with files list and pagination token
    """
    # Build query string
    query_parts = []

    if folder_id and folder_id != 'root':
        query_parts.append(f"'{folder_id}' in parents")

    if mime_type:
        query_parts.append(f"mimeType='{mime_type}'")

    # Exclude trashed files by default
    query_parts.append("trashed=false")

    query = ' and '.join(query_parts) if query_parts else None

    # Fields to retrieve
    fields = "nextPageToken, files(id, name, mimeType, size, modifiedTime, createdTime, owners, parents, webViewLink)"

    # Execute request
    request_params = {
        'pageSize': min(page_size, 1000),
        'fields': fields,
        'supportsAllDrives': True,
        'includeItemsFromAllDrives': True
    }

    if query:
        request_params['q'] = query
    if page_token:
        request_params['pageToken'] = page_token
    if order_by:
        request_params['orderBy'] = order_by

    results = service.files().list(**request_params).execute()
    return results


def format_human_readable(results: Dict[str, Any]) -> str:
    """Format results as human-readable text."""
    files = results.get('files', [])
    next_token = results.get('nextPageToken')

    if not files:
        return "No files found."

    output = []
    output.append(f"Found {len(files)} file(s):\n")

    for file in files:
        output.append(f"Name: {file.get('name')}")
        output.append(f"  ID: {file.get('id')}")
        output.append(f"  Type: {file.get('mimeType')}")
        if file.get('size'):
            size_mb = int(file.get('size')) / (1024 * 1024)
            output.append(f"  Size: {size_mb:.2f} MB")
        output.append(f"  Modified: {file.get('modifiedTime')}")
        if file.get('webViewLink'):
            output.append(f"  Link: {file.get('webViewLink')}")
        output.append("")

    if next_token:
        output.append(f"Next page token: {next_token}")

    return '\n'.join(output)


def main():
    parser = argparse.ArgumentParser(
        description='List files in Google Drive',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --json
  %(prog)s --folder-id "abc123" --mime-type "application/pdf" --json
  %(prog)s --order-by "modifiedTime desc" --page-size 50 --json
        """
    )

    parser.add_argument('--folder-id', default='root',
                        help='Parent folder ID (default: root)')
    parser.add_argument('--page-size', type=int, default=100,
                        help='Results per page (default: 100, max: 1000)')
    parser.add_argument('--page-token',
                        help='Token for pagination')
    parser.add_argument('--mime-type',
                        help='Filter by MIME type')
    parser.add_argument('--order-by',
                        help='Sort order (e.g., "name", "modifiedTime desc")')
    parser.add_argument('--json', action='store_true',
                        help='Output as JSON')

    args = parser.parse_args()

    try:
        # Authenticate
        service = get_drive_service()

        # List files
        results = list_files(
            service,
            folder_id=args.folder_id,
            page_size=args.page_size,
            page_token=args.page_token,
            mime_type=args.mime_type,
            order_by=args.order_by
        )

        # Format output
        if args.json:
            output = {
                'success': True,
                'data': {
                    'files': results.get('files', []),
                    'nextPageToken': results.get('nextPageToken'),
                    'totalFiles': len(results.get('files', []))
                }
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(results))

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
        error_output = {
            'success': False,
            'error': {
                'type': 'PermissionError',
                'message': str(e),
                'suggestions': [
                    'Share the folder/files with the service account',
                    'Verify the folder ID is correct',
                    'Check service account permissions'
                ]
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
                'suggestions': [
                    'Wait a few minutes and try again',
                    'Consider reducing page size',
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
                'message': str(e)
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
