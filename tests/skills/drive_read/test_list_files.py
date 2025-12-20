"""
Tests for drive-read/scripts/list_files.py
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock, Mock
from googleapiclient.errors import HttpError

# Add drive-read scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_read_scripts = project_root / "skills" / "drive-read" / "scripts"
sys.path.insert(0, str(drive_read_scripts))


class TestListFiles:
    """Test file listing functionality."""

    def test_list_files_success(self, mock_drive_service):
        """Test successful file listing."""
        from list_files import list_files

        result = list_files(
            mock_drive_service,
            folder_id='root',
            page_size=100
        )

        assert 'files' in result
        assert len(result['files']) == 2
        assert result['files'][0]['name'] == 'test-document.pdf'

    def test_list_files_with_folder_filter(self, mock_drive_service):
        """Test file listing with folder filter."""
        from list_files import list_files

        result = list_files(
            mock_drive_service,
            folder_id='abc123'
        )

        # Verify the query was constructed correctly
        call_args = mock_drive_service.files().list.call_args
        assert call_args is not None
        query = call_args[1]['q']
        assert "'abc123' in parents" in query
        assert "trashed=false" in query

    def test_list_files_with_mime_type_filter(self, mock_drive_service):
        """Test file listing with MIME type filter."""
        from list_files import list_files

        result = list_files(
            mock_drive_service,
            mime_type='application/pdf'
        )

        # Verify the query was constructed correctly
        call_args = mock_drive_service.files().list.call_args
        query = call_args[1]['q']
        assert "mimeType='application/pdf'" in query

    def test_list_files_with_order_by(self, mock_drive_service):
        """Test file listing with sorting."""
        from list_files import list_files

        result = list_files(
            mock_drive_service,
            order_by='modifiedTime desc'
        )

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['orderBy'] == 'modifiedTime desc'

    def test_list_files_pagination(self, mock_drive_service):
        """Test pagination with page tokens."""
        from list_files import list_files

        mock_drive_service.files().list().execute.return_value = {
            'files': [],
            'nextPageToken': 'token123'
        }

        result = list_files(
            mock_drive_service,
            page_token='prev_token'
        )

        assert result['nextPageToken'] == 'token123'
        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['pageToken'] == 'prev_token'

    def test_list_files_page_size_limit(self, mock_drive_service):
        """Test page size is capped at 1000."""
        from list_files import list_files

        list_files(mock_drive_service, page_size=2000)

        call_args = mock_drive_service.files().list.call_args
        assert call_args[1]['pageSize'] == 1000  # Capped at 1000


class TestFormatHumanReadable:
    """Test human-readable output formatting."""

    def test_format_empty_results(self):
        """Test formatting when no files found."""
        from list_files import format_human_readable

        output = format_human_readable({'files': []})
        assert "No files found" in output

    def test_format_with_files(self):
        """Test formatting with file results."""
        from list_files import format_human_readable

        results = {
            'files': [
                {
                    'id': '123',
                    'name': 'test.pdf',
                    'mimeType': 'application/pdf',
                    'size': '1048576',  # 1 MB
                    'modifiedTime': '2025-01-15T10:30:00.000Z',
                    'webViewLink': 'https://drive.google.com/file/d/123/view'
                }
            ],
            'nextPageToken': 'token456'
        }

        output = format_human_readable(results)

        assert 'test.pdf' in output
        assert '123' in output
        assert 'application/pdf' in output
        assert '1.00 MB' in output
        assert 'token456' in output
