#!/usr/bin/env python3
"""
Google Drive Advanced Search

Search for files in Google Drive using multiple filter criteria.
Supports filtering by name, MIME type, modification time, owner, and more.
"""

import sys
import json
import argparse
from datetime import datetime
from typing import Optional, Dict, Any, List

from gdrive_auth import get_drive_service, DriveAuthError
from gdrive_retry import exponential_backoff_retry, PermanentError, RetryableError


@exponential_backoff_retry(max_retries=5)
def search_files(
    service,
    name_contains: Optional[str] = None,
    mime_type: Optional[str] = None,
    modified_after: Optional[str] = None,
    modified_before: Optional[str] = None,
    owner: Optional[str] = None,
    in_folder: Optional[str] = None,
    starred: bool = False,
    page_size: int = 100,
    page_token: Optional[str] = None,
    order_by: Optional[str] = None
) -> Dict[str, Any]:
    """
    Search for files in Google Drive with advanced filters.

    Args:
        service: Authenticated Google Drive service
        name_contains: Search for files with names containing this text
        mime_type: Filter by MIME type
        modified_after: Files modified after this date (ISO 8601)
        modified_before: Files modified before this date (ISO 8601)
        owner: Filter by owner email address
        in_folder: Search within a specific folder ID
        starred: Only return starred files
        page_size: Number of results per page (max 1000)
        page_token: Token for pagination
        order_by: Field to sort by (e.g., "modifiedTime desc")

    Returns:
        Dictionary with search results and pagination info

    Raises:
        PermanentError: For non-retryable API errors
        RetryableError: When max retries exceeded
    """
    # Build query string from filters
    query_parts = []

    # Name filter
    if name_contains:
        # Escape single quotes in the search term
        escaped_name = name_contains.replace("'", "\\'")
        query_parts.append(f"name contains '{escaped_name}'")

    # MIME type filter
    if mime_type:
        query_parts.append(f"mimeType='{mime_type}'")

    # Modification time filters
    if modified_after:
        query_parts.append(f"modifiedTime > '{modified_after}'")

    if modified_before:
        query_parts.append(f"modifiedTime < '{modified_before}'")

    # Owner filter
    if owner:
        query_parts.append(f"'{owner}' in owners")

    # Folder filter
    if in_folder:
        query_parts.append(f"'{in_folder}' in parents")

    # Starred filter
    if starred:
        query_parts.append("starred = true")

    # Always exclude trashed files
    query_parts.append("trashed = false")

    # Combine all query parts with AND
    query = ' and '.join(query_parts) if query_parts else "trashed = false"

    # Define fields to return
    fields = (
        "nextPageToken, files("
        "id, name, mimeType, size, modifiedTime, createdTime, "
        "owners, parents, webViewLink, starred, description"
        ")"
    )

    # Cap page size at 1000 (API limit)
    page_size = min(page_size, 1000)

    # Build request parameters
    request_params = {
        'q': query,
        'pageSize': page_size,
        'fields': fields,
        'supportsAllDrives': True,
        'includeItemsFromAllDrives': True,
    }

    if page_token:
        request_params['pageToken'] = page_token

    if order_by:
        request_params['orderBy'] = order_by

    # Execute search
    results = service.files().list(**request_params).execute()

    # Add total count
    files = results.get('files', [])
    results['totalFiles'] = len(files)

    return results


def validate_date_format(date_string: str) -> bool:
    """
    Validate that date string is in ISO 8601 format with time component.

    Args:
        date_string: Date string to validate

    Returns:
        True if valid, raises ValueError if invalid
    """
    # Google Drive API requires RFC 3339 format (date + time + timezone)
    # Must contain 'T' separator between date and time
    if 'T' not in date_string:
        raise ValueError(
            f"Invalid date format: {date_string}. "
            f"Expected ISO 8601 format with time (e.g., '2025-12-15T00:00:00Z')"
        )

    try:
        # Try to parse the date
        datetime.fromisoformat(date_string.replace('Z', '+00:00'))
        return True
    except ValueError as e:
        raise ValueError(
            f"Invalid date format: {date_string}. "
            f"Expected ISO 8601 format (e.g., '2025-12-15T00:00:00Z')"
        ) from e


def format_human_readable(results: Dict[str, Any], search_params: Dict[str, Any]) -> str:
    """
    Format search results in human-readable format.

    Args:
        results: Search results from Drive API
        search_params: Original search parameters for display

    Returns:
        Formatted string for display
    """
    lines = []

    # Header with search criteria
    lines.append("=" * 80)
    lines.append("GOOGLE DRIVE SEARCH RESULTS")
    lines.append("=" * 80)

    # Display active filters
    active_filters = []
    if search_params.get('name_contains'):
        active_filters.append(f"Name contains: {search_params['name_contains']}")
    if search_params.get('mime_type'):
        active_filters.append(f"MIME type: {search_params['mime_type']}")
    if search_params.get('modified_after'):
        active_filters.append(f"Modified after: {search_params['modified_after']}")
    if search_params.get('modified_before'):
        active_filters.append(f"Modified before: {search_params['modified_before']}")
    if search_params.get('owner'):
        active_filters.append(f"Owner: {search_params['owner']}")
    if search_params.get('in_folder'):
        active_filters.append(f"In folder: {search_params['in_folder']}")
    if search_params.get('starred'):
        active_filters.append("Starred only: Yes")

    if active_filters:
        lines.append("\nActive Filters:")
        for filter_desc in active_filters:
            lines.append(f"  • {filter_desc}")

    lines.append("")

    # Files
    files = results.get('files', [])

    if not files:
        lines.append("No files found matching the search criteria.")
    else:
        lines.append(f"Found {len(files)} file(s):\n")

        for i, file_info in enumerate(files, 1):
            lines.append(f"{i}. {file_info.get('name', 'Untitled')}")
            lines.append(f"   ID: {file_info.get('id', 'N/A')}")
            lines.append(f"   Type: {file_info.get('mimeType', 'Unknown')}")

            # Size (if available)
            if 'size' in file_info:
                size_bytes = int(file_info['size'])
                size_mb = size_bytes / (1024 * 1024)
                if size_mb < 1:
                    lines.append(f"   Size: {size_bytes / 1024:.2f} KB")
                else:
                    lines.append(f"   Size: {size_mb:.2f} MB")
            else:
                lines.append("   Size: N/A (Google Doc)")

            # Modified time
            if 'modifiedTime' in file_info:
                lines.append(f"   Modified: {file_info['modifiedTime']}")

            # Owners
            owners = file_info.get('owners', [])
            if owners:
                owner_names = [o.get('displayName', o.get('emailAddress', 'Unknown')) for o in owners]
                lines.append(f"   Owner: {', '.join(owner_names)}")

            # Starred
            if file_info.get('starred'):
                lines.append("   Starred: Yes")

            # Link
            if 'webViewLink' in file_info:
                lines.append(f"   Link: {file_info['webViewLink']}")

            lines.append("")  # Blank line between files

    # Pagination info
    if 'nextPageToken' in results:
        lines.append("-" * 80)
        lines.append(f"More results available. Use --page-token {results['nextPageToken']}")

    lines.append("=" * 80)

    return '\n'.join(lines)


def main():
    """Main entry point for search_files script."""
    parser = argparse.ArgumentParser(
        description='Search for files in Google Drive with advanced filters',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Search for PDF files containing "invoice"
  %(prog)s --name-contains "invoice" --mime-type "application/pdf"

  # Find files modified in the last week
  %(prog)s --modified-after "2025-12-13T00:00:00Z" --order-by "modifiedTime desc"

  # Search within a specific folder
  %(prog)s --in-folder "1a2b3c4d5e" --name-contains "report"

  # Find starred spreadsheets
  %(prog)s --starred --mime-type "application/vnd.google-apps.spreadsheet"
        """
    )

    # Search filters
    parser.add_argument(
        '--name-contains',
        help='Search for files with names containing this text'
    )
    parser.add_argument(
        '--mime-type',
        help='Filter by MIME type (e.g., application/pdf)'
    )
    parser.add_argument(
        '--modified-after',
        help='Files modified after this date (ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ)'
    )
    parser.add_argument(
        '--modified-before',
        help='Files modified before this date (ISO 8601 format: YYYY-MM-DDTHH:MM:SSZ)'
    )
    parser.add_argument(
        '--owner',
        help='Filter by owner email address'
    )
    parser.add_argument(
        '--in-folder',
        help='Search within a specific folder ID'
    )
    parser.add_argument(
        '--starred',
        action='store_true',
        help='Only return starred files'
    )

    # Pagination and sorting
    parser.add_argument(
        '--page-size',
        type=int,
        default=100,
        help='Number of results per page (default: 100, max: 1000)'
    )
    parser.add_argument(
        '--page-token',
        help='Pagination token for next page of results'
    )
    parser.add_argument(
        '--order-by',
        help='Sort results by field (e.g., "modifiedTime desc", "name")'
    )

    # Output format
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results in JSON format'
    )

    args = parser.parse_args()

    try:
        # Validate date formats if provided
        if args.modified_after:
            validate_date_format(args.modified_after)
        if args.modified_before:
            validate_date_format(args.modified_before)

        # Get authenticated service
        service = get_drive_service()

        # Store search parameters for display
        search_params = {
            'name_contains': args.name_contains,
            'mime_type': args.mime_type,
            'modified_after': args.modified_after,
            'modified_before': args.modified_before,
            'owner': args.owner,
            'in_folder': args.in_folder,
            'starred': args.starred,
        }

        # Execute search
        results = search_files(
            service,
            name_contains=args.name_contains,
            mime_type=args.mime_type,
            modified_after=args.modified_after,
            modified_before=args.modified_before,
            owner=args.owner,
            in_folder=args.in_folder,
            starred=args.starred,
            page_size=args.page_size,
            page_token=args.page_token,
            order_by=args.order_by
        )

        # Output results
        if args.json:
            output = {
                'success': True,
                'data': results,
                'searchParams': search_params
            }
            print(json.dumps(output, indent=2))
        else:
            print(format_human_readable(results, search_params))

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
                    'Verify search parameters are correct',
                    'Check that you have access to the requested files/folders',
                    'Ensure date formats are valid (ISO 8601)'
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
                    'Consider reducing page size',
                    'Check Google Cloud Console for quota limits'
                ]
            }
        }
        print(json.dumps(error_output, indent=2), file=sys.stderr)
        sys.exit(1)

    except ValueError as e:
        error_output = {
            'success': False,
            'error': {
                'type': 'ValidationError',
                'message': str(e),
                'suggestions': [
                    'Check date format (should be ISO 8601: YYYY-MM-DDTHH:MM:SSZ)',
                    'Verify all parameters are valid'
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
