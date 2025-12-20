"""
Tests for drive-search/scripts/search_files.py
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock, Mock
from googleapiclient.errors import HttpError

# Add drive-search scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_search_scripts = project_root / "skills" / "drive-search" / "scripts"
sys.path.insert(0, str(drive_search_scripts))


class TestSearchFiles:
    """Test advanced search functionality."""

    def test_search_files_basic(self, mock_drive_service):
        """Test basic search without filters."""
        from search_files import search_files

        result = search_files(mock_drive_service)

        assert 'files' in result
        # Verify basic query for non-trashed files
        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert 'trashed = false' in query

    def test_search_files_name_contains(self, mock_drive_service):
        """Test search by name."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            name_contains='invoice'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "name contains 'invoice'" in query
        assert 'trashed = false' in query

    def test_search_files_name_with_quotes(self, mock_drive_service):
        """Test search by name with special characters (quotes)."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            name_contains="test's file"
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        # Should escape single quotes
        assert "name contains 'test\\'s file'" in query

    def test_search_files_mime_type(self, mock_drive_service):
        """Test search by MIME type."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            mime_type='application/pdf'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "mimeType='application/pdf'" in query

    def test_search_files_modified_after(self, mock_drive_service):
        """Test search by modified after date."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            modified_after='2025-12-01T00:00:00Z'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "modifiedTime > '2025-12-01T00:00:00Z'" in query

    def test_search_files_modified_before(self, mock_drive_service):
        """Test search by modified before date."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            modified_before='2025-12-31T23:59:59Z'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "modifiedTime < '2025-12-31T23:59:59Z'" in query

    def test_search_files_owner(self, mock_drive_service):
        """Test search by owner email."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            owner='user@example.com'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "'user@example.com' in owners" in query

    def test_search_files_in_folder(self, mock_drive_service):
        """Test search within specific folder."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            in_folder='abc123'
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "'abc123' in parents" in query

    def test_search_files_starred(self, mock_drive_service):
        """Test search for starred files only."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            starred=True
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert 'starred = true' in query

    def test_search_files_combined_filters(self, mock_drive_service):
        """Test search with multiple filters combined."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            name_contains='report',
            mime_type='application/pdf',
            modified_after='2025-12-01T00:00:00Z',
            in_folder='folder123',
            starred=True
        )

        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']

        # All filters should be present, combined with 'and'
        assert "name contains 'report'" in query
        assert "mimeType='application/pdf'" in query
        assert "modifiedTime > '2025-12-01T00:00:00Z'" in query
        assert "'folder123' in parents" in query
        assert 'starred = true' in query
        assert 'trashed = false' in query
        assert ' and ' in query

    def test_search_files_pagination(self, mock_drive_service):
        """Test pagination parameters."""
        from search_files import search_files

        mock_drive_service.files().list().execute.return_value = {
            'files': [],
            'nextPageToken': 'token456'
        }

        result = search_files(
            mock_drive_service,
            page_size=50,
            page_token='prev_token'
        )

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['pageSize'] == 50
        assert call_args[1]['pageToken'] == 'prev_token'
        assert result['nextPageToken'] == 'token456'

    def test_search_files_page_size_limit(self, mock_drive_service):
        """Test page size is capped at 1000."""
        from search_files import search_files

        search_files(mock_drive_service, page_size=2000)

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['pageSize'] == 1000  # Capped at 1000

    def test_search_files_order_by(self, mock_drive_service):
        """Test sorting results."""
        from search_files import search_files

        result = search_files(
            mock_drive_service,
            order_by='modifiedTime desc'
        )

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['orderBy'] == 'modifiedTime desc'

    def test_search_files_supports_shared_drives(self, mock_drive_service):
        """Test that shared drives support is enabled."""
        from search_files import search_files

        result = search_files(mock_drive_service)

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['supportsAllDrives'] is True
        assert call_args[1]['includeItemsFromAllDrives'] is True

    def test_search_files_total_count(self, mock_drive_service):
        """Test that total file count is added to results."""
        from search_files import search_files

        mock_drive_service.files().list().execute.return_value = {
            'files': [
                {'id': '1', 'name': 'file1.pdf'},
                {'id': '2', 'name': 'file2.pdf'},
                {'id': '3', 'name': 'file3.pdf'}
            ]
        }

        result = search_files(mock_drive_service)

        assert result['totalFiles'] == 3


class TestDateValidation:
    """Test date format validation."""

    def test_validate_date_valid_formats(self):
        """Test that valid ISO 8601 dates are accepted."""
        from search_files import validate_date_format

        # These should not raise exceptions
        assert validate_date_format('2025-12-15T00:00:00Z')
        assert validate_date_format('2025-12-15T10:30:45Z')
        assert validate_date_format('2025-01-01T00:00:00Z')

    def test_validate_date_invalid_format(self):
        """Test that invalid date formats are rejected."""
        from search_files import validate_date_format

        with pytest.raises(ValueError, match="Invalid date format"):
            validate_date_format('2025-12-15')  # Missing time

        with pytest.raises(ValueError, match="Invalid date format"):
            validate_date_format('12/15/2025')  # Wrong format

        with pytest.raises(ValueError, match="Invalid date format"):
            validate_date_format('not a date')


class TestFormatHumanReadable:
    """Test human-readable output formatting."""

    def test_format_no_results(self):
        """Test formatting when no files found."""
        from search_files import format_human_readable

        results = {'files': []}
        search_params = {'name_contains': 'test'}

        output = format_human_readable(results, search_params)

        assert 'GOOGLE DRIVE SEARCH RESULTS' in output
        assert 'No files found' in output
        assert 'Name contains: test' in output

    def test_format_with_results(self):
        """Test formatting with search results."""
        from search_files import format_human_readable

        results = {
            'files': [
                {
                    'id': '123',
                    'name': 'test.pdf',
                    'mimeType': 'application/pdf',
                    'size': '2097152',  # 2 MB
                    'modifiedTime': '2025-12-15T10:30:00.000Z',
                    'owners': [{'displayName': 'Test User', 'emailAddress': 'test@example.com'}],
                    'webViewLink': 'https://drive.google.com/file/d/123/view',
                    'starred': True
                }
            ],
            'totalFiles': 1
        }
        search_params = {
            'name_contains': 'test',
            'mime_type': 'application/pdf'
        }

        output = format_human_readable(results, search_params)

        assert 'test.pdf' in output
        assert '123' in output
        assert 'application/pdf' in output
        assert '2.00 MB' in output
        assert 'Test User' in output
        assert 'Starred: Yes' in output
        assert 'Name contains: test' in output
        assert 'MIME type: application/pdf' in output

    def test_format_with_google_doc(self):
        """Test formatting Google Docs (no size field)."""
        from search_files import format_human_readable

        results = {
            'files': [
                {
                    'id': '456',
                    'name': 'Google Doc',
                    'mimeType': 'application/vnd.google-apps.document',
                    'modifiedTime': '2025-12-15T10:30:00.000Z',
                    'owners': [{'emailAddress': 'test@example.com'}]
                }
            ],
            'totalFiles': 1
        }
        search_params = {}

        output = format_human_readable(results, search_params)

        assert 'Google Doc' in output
        assert 'Size: N/A (Google Doc)' in output

    def test_format_with_pagination(self):
        """Test formatting with pagination token."""
        from search_files import format_human_readable

        results = {
            'files': [{'id': '1', 'name': 'file.pdf'}],
            'totalFiles': 1,
            'nextPageToken': 'next_token_123'
        }
        search_params = {}

        output = format_human_readable(results, search_params)

        assert 'More results available' in output
        assert 'next_token_123' in output

    def test_format_all_filters(self):
        """Test formatting with all filter types displayed."""
        from search_files import format_human_readable

        results = {'files': [], 'totalFiles': 0}
        search_params = {
            'name_contains': 'report',
            'mime_type': 'application/pdf',
            'modified_after': '2025-12-01T00:00:00Z',
            'modified_before': '2025-12-31T23:59:59Z',
            'owner': 'user@example.com',
            'in_folder': 'folder123',
            'starred': True
        }

        output = format_human_readable(results, search_params)

        assert 'Name contains: report' in output
        assert 'MIME type: application/pdf' in output
        assert 'Modified after: 2025-12-01T00:00:00Z' in output
        assert 'Modified before: 2025-12-31T23:59:59Z' in output
        assert 'Owner: user@example.com' in output
        assert 'In folder: folder123' in output
        assert 'Starred only: Yes' in output

    def test_format_file_size_kb(self):
        """Test formatting file size in KB for small files."""
        from search_files import format_human_readable

        results = {
            'files': [
                {
                    'id': '789',
                    'name': 'small.txt',
                    'size': '512',  # 512 bytes
                }
            ],
            'totalFiles': 1
        }
        search_params = {}

        output = format_human_readable(results, search_params)

        assert '0.50 KB' in output


class TestErrorHandling:
    """Test error handling in search_files."""

    def test_search_files_handles_http_error(self, mock_drive_service):
        """Test that HTTP errors are properly wrapped."""
        from search_files import search_files
        from gdrive_retry import PermanentError

        # Mock a 404 error (permanent error)
        mock_drive_service.files().list().execute.side_effect = HttpError(
            resp=Mock(status=404),
            content=b'{}'
        )

        with pytest.raises(PermanentError):
            search_files(mock_drive_service)

    def test_search_files_retries_transient_errors(self, mock_drive_service):
        """Test that transient errors trigger retries."""
        from search_files import search_files

        call_count = 0

        def side_effect():
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise HttpError(
                    resp=Mock(status=429),
                    content=b'{}'
                )
            return {'files': [], 'totalFiles': 0}

        mock_drive_service.files().list().execute.side_effect = side_effect

        with patch('time.sleep'):  # Mock sleep to speed up test
            result = search_files(mock_drive_service)

        assert call_count == 3  # Should retry twice then succeed
        assert result['totalFiles'] == 0


class TestMainFunction:
    """Test the main CLI function."""

    @patch('search_files.get_drive_service')
    def test_main_json_output(self, mock_get_service, mock_drive_service, capsys):
        """Test main function with JSON output."""
        from search_files import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().list().execute.return_value = {
            'files': [{'id': '123', 'name': 'test.pdf'}],
            'totalFiles': 1
        }

        with patch('sys.argv', ['search_files.py', '--name-contains', 'test', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert '"success": true' in captured.out
        assert '"test.pdf"' in captured.out

    @patch('search_files.get_drive_service')
    def test_main_human_readable_output(self, mock_get_service, mock_drive_service, capsys):
        """Test main function with human-readable output."""
        from search_files import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().list().execute.return_value = {
            'files': [{'id': '123', 'name': 'test.pdf'}],
            'totalFiles': 1
        }

        with patch('sys.argv', ['search_files.py', '--name-contains', 'test']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert 'GOOGLE DRIVE SEARCH RESULTS' in captured.out
        assert 'test.pdf' in captured.out

    @patch('search_files.get_drive_service')
    def test_main_invalid_date_format(self, mock_get_service, mock_drive_service, capsys):
        """Test main function with invalid date format."""
        from search_files import main

        mock_get_service.return_value = mock_drive_service

        with patch('sys.argv', ['search_files.py', '--modified-after', 'invalid-date']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert 'ValidationError' in captured.err
        assert 'Invalid date format' in captured.err

    @patch('search_files.get_drive_service')
    def test_main_auth_error(self, mock_get_service, capsys):
        """Test main function with authentication error."""
        from search_files import main
        from gdrive_auth import DriveAuthError

        mock_get_service.side_effect = DriveAuthError("Auth failed")

        with patch('sys.argv', ['search_files.py']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert 'AuthenticationError' in captured.err
        assert 'Auth failed' in captured.err
