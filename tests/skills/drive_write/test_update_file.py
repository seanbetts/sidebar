"""
Tests for drive-write/scripts/update_file.py
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock, Mock
from googleapiclient.errors import HttpError

# Add drive-write scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_write_scripts = project_root / "skills" / "drive-write" / "scripts"
sys.path.insert(0, str(drive_write_scripts))


class TestUpdateFile:
    """Test file update functionality."""

    def test_update_file_content_only(self, mock_drive_service, tmp_path):
        """Test updating only file content."""
        from update_file import update_file

        # Create a temporary file for new content
        new_content = tmp_path / "new_content.txt"
        new_content.write_text("updated content")

        # Mock getting existing file info
        mock_drive_service.files().get().execute.return_value = {
            'mimeType': 'text/plain'
        }

        # Mock update response
        mock_drive_service.files().update().execute.return_value = {
            'id': '123',
            'name': 'original.txt',
            'mimeType': 'text/plain',
            'size': '15'
        }

        result = update_file(
            mock_drive_service,
            file_id='123',
            content_path=str(new_content)
        )

        assert result['id'] == '123'

        # Verify update was called with media
        call_args = mock_drive_service.files().update.call_args
        assert call_args[1]['media_body'] is not None

    def test_update_file_name_only(self, mock_drive_service):
        """Test updating only file name."""
        from update_file import update_file

        mock_drive_service.files().update().execute.return_value = {
            'id': '456',
            'name': 'new_name.txt'
        }

        result = update_file(
            mock_drive_service,
            file_id='456',
            name='new_name.txt'
        )

        assert result['name'] == 'new_name.txt'

        # Verify name was updated
        call_args = mock_drive_service.files().update.call_args
        assert call_args[1]['body']['name'] == 'new_name.txt'
        assert call_args[1]['media_body'] is None

    def test_update_file_description_only(self, mock_drive_service):
        """Test updating only description."""
        from update_file import update_file

        mock_drive_service.files().update().execute.return_value = {
            'id': '789',
            'description': 'Updated description'
        }

        result = update_file(
            mock_drive_service,
            file_id='789',
            description='Updated description'
        )

        # Verify description was updated
        call_args = mock_drive_service.files().update.call_args
        assert call_args[1]['body']['description'] == 'Updated description'

    def test_update_file_multiple_fields(self, mock_drive_service, tmp_path):
        """Test updating content, name, and description together."""
        from update_file import update_file

        new_content = tmp_path / "new.txt"
        new_content.write_text("new content")

        mock_drive_service.files().get().execute.return_value = {
            'mimeType': 'text/plain'
        }

        mock_drive_service.files().update().execute.return_value = {
            'id': '111',
            'name': 'updated.txt',
            'description': 'Updated',
            'size': '11'
        }

        result = update_file(
            mock_drive_service,
            file_id='111',
            content_path=str(new_content),
            name='updated.txt',
            description='Updated'
        )

        # Verify all fields were updated
        call_args = mock_drive_service.files().update.call_args
        assert call_args[1]['body']['name'] == 'updated.txt'
        assert call_args[1]['body']['description'] == 'Updated'
        assert call_args[1]['media_body'] is not None

    def test_update_file_clear_description(self, mock_drive_service):
        """Test clearing description with empty string."""
        from update_file import update_file

        mock_drive_service.files().update().execute.return_value = {
            'id': '222',
            'description': ''
        }

        result = update_file(
            mock_drive_service,
            file_id='222',
            description=''
        )

        # Verify description was set to empty string
        call_args = mock_drive_service.files().update.call_args
        assert call_args[1]['body']['description'] == ''

    def test_update_file_no_updates_specified(self, mock_drive_service):
        """Test that error is raised when no updates specified."""
        from update_file import update_file
        from gdrive_retry import PermanentError

        with pytest.raises(PermanentError, match="Must specify at least one"):
            update_file(
                mock_drive_service,
                file_id='333'
            )

    def test_update_file_content_not_found(self, mock_drive_service):
        """Test error when content file doesn't exist."""
        from update_file import update_file
        from gdrive_retry import PermanentError

        with pytest.raises(PermanentError, match="Content file not found"):
            update_file(
                mock_drive_service,
                file_id='444',
                content_path='/nonexistent/file.txt'
            )

    def test_update_file_preserves_mime_type(self, mock_drive_service, tmp_path):
        """Test that original MIME type is preserved."""
        from update_file import update_file

        new_content = tmp_path / "content.pdf"
        new_content.write_bytes(b'pdf content')

        # Mock existing file with PDF MIME type
        mock_drive_service.files().get().execute.return_value = {
            'mimeType': 'application/pdf'
        }

        mock_drive_service.files().update().execute.return_value = {
            'id': '555',
            'mimeType': 'application/pdf'
        }

        with patch('update_file.MediaFileUpload') as mock_media:
            result = update_file(
                mock_drive_service,
                file_id='555',
                content_path=str(new_content)
            )

            # Verify MediaFileUpload was called with correct MIME type
            mock_media.assert_called_once()
            call_args = mock_media.call_args
            assert call_args[1]['mimetype'] == 'application/pdf'

    def test_update_file_supports_shared_drives(self, mock_drive_service):
        """Test that shared drives support is enabled."""
        from update_file import update_file

        mock_drive_service.files().update().execute.return_value = {
            'id': '666',
            'name': 'updated.txt'
        }

        result = update_file(
            mock_drive_service,
            file_id='666',
            name='updated.txt'
        )

        # Verify update supports shared drives
        update_call_args = mock_drive_service.files().update.call_args
        assert update_call_args[1]['supportsAllDrives'] is True


class TestFormatFileSize:
    """Test file size formatting."""

    def test_format_bytes(self):
        """Test formatting bytes."""
        from update_file import format_file_size

        assert format_file_size(512) == "512 B"

    def test_format_kilobytes(self):
        """Test formatting kilobytes."""
        from update_file import format_file_size

        assert format_file_size(2048) == "2.00 KB"

    def test_format_megabytes(self):
        """Test formatting megabytes."""
        from update_file import format_file_size

        assert format_file_size(5 * 1024 * 1024) == "5.00 MB"


class TestFormatHumanReadable:
    """Test human-readable output formatting."""

    def test_format_content_update(self):
        """Test formatting with content update."""
        from update_file import format_human_readable

        file_info = {
            'id': '123',
            'name': 'file.txt',
            'mimeType': 'text/plain',
            'size': '1024',
            'modifiedTime': '2025-12-20T10:30:00.000Z'
        }

        updates = {
            'content_updated': True,
            'content_path': '/path/to/new.txt',
            'name_updated': False,
            'description_updated': False
        }

        output = format_human_readable(file_info, updates)

        assert 'FILE UPDATED SUCCESSFULLY' in output
        assert 'Content updated from: /path/to/new.txt' in output

    def test_format_name_update(self):
        """Test formatting with name update."""
        from update_file import format_human_readable

        file_info = {
            'id': '456',
            'name': 'new_name.txt'
        }

        updates = {
            'content_updated': False,
            'name_updated': True,
            'new_name': 'new_name.txt',
            'description_updated': False
        }

        output = format_human_readable(file_info, updates)

        assert 'Name changed to: new_name.txt' in output

    def test_format_description_cleared(self):
        """Test formatting when description is cleared."""
        from update_file import format_human_readable

        file_info = {
            'id': '789',
            'name': 'file.txt'
        }

        updates = {
            'content_updated': False,
            'name_updated': False,
            'description_updated': True,
            'new_description': ''
        }

        output = format_human_readable(file_info, updates)

        assert 'Description cleared' in output


class TestMainFunction:
    """Test the main CLI function."""

    @patch('update_file.get_drive_service')
    def test_main_update_name(self, mock_get_service, mock_drive_service, capsys):
        """Test updating file name via main function."""
        from update_file import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().update().execute.return_value = {
            'id': '123',
            'name': 'new_name.txt',
            'mimeType': 'text/plain'
        }

        with patch('sys.argv', ['update_file.py', '123', '--name', 'new_name.txt', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert '"success": true' in captured.out

    @patch('update_file.get_drive_service')
    def test_main_no_updates_specified(self, mock_get_service, capsys):
        """Test error when no updates are specified."""
        from update_file import main

        mock_get_service.return_value = MagicMock()

        with patch('sys.argv', ['update_file.py', '123']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        # Should exit with error due to no updates
        assert exc_info.value.code == 2  # argparse error code

    @patch('update_file.get_drive_service')
    def test_main_content_file_not_found(self, mock_get_service, capsys):
        """Test error when content file doesn't exist."""
        from update_file import main

        mock_get_service.return_value = MagicMock()

        with patch('sys.argv', ['update_file.py', '123', '--content-path', '/nonexistent.txt']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert 'FileNotFoundError' in captured.err

    @patch('update_file.get_drive_service')
    def test_main_update_description(self, mock_get_service, mock_drive_service, capsys):
        """Test updating description via main function."""
        from update_file import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().update().execute.return_value = {
            'id': '456',
            'name': 'file.txt',
            'description': 'New description'
        }

        with patch('sys.argv', ['update_file.py', '456', '--description', 'New description', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0
