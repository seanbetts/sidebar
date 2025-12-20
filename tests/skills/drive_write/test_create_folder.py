"""
Tests for drive-write/scripts/create_folder.py
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


class TestCreateFolder:
    """Test folder creation functionality."""

    def test_create_folder_basic(self, mock_drive_service):
        """Test basic folder creation."""
        from create_folder import create_folder

        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder123',
            'name': 'Test Folder',
            'mimeType': 'application/vnd.google-apps.folder'
        }

        result = create_folder(
            mock_drive_service,
            folder_name='Test Folder'
        )

        assert result['id'] == 'folder123'
        assert result['name'] == 'Test Folder'
        assert result['mimeType'] == 'application/vnd.google-apps.folder'

    def test_create_folder_with_parent(self, mock_drive_service):
        """Test folder creation in specific parent."""
        from create_folder import create_folder

        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder456',
            'name': 'Subfolder',
            'parents': ['parent789']
        }

        result = create_folder(
            mock_drive_service,
            folder_name='Subfolder',
            parent_id='parent789'
        )

        # Verify parent was set
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['parents'] == ['parent789']

    def test_create_folder_with_description(self, mock_drive_service):
        """Test folder creation with description."""
        from create_folder import create_folder

        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder111',
            'name': 'Archive',
            'description': 'Old files'
        }

        result = create_folder(
            mock_drive_service,
            folder_name='Archive',
            description='Old files'
        )

        # Verify description was set
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['description'] == 'Old files'

    def test_create_folder_mime_type(self, mock_drive_service):
        """Test that folder MIME type is set correctly."""
        from create_folder import create_folder

        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder222',
            'name': 'Test'
        }

        result = create_folder(
            mock_drive_service,
            folder_name='Test'
        )

        # Verify MIME type was set to folder
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['mimeType'] == 'application/vnd.google-apps.folder'

    def test_create_folder_supports_shared_drives(self, mock_drive_service):
        """Test that shared drives support is enabled."""
        from create_folder import create_folder

        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder333',
            'name': 'Test'
        }

        result = create_folder(
            mock_drive_service,
            folder_name='Test'
        )

        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['supportsAllDrives'] is True


class TestFormatHumanReadable:
    """Test human-readable output formatting."""

    def test_format_basic_folder(self):
        """Test basic folder formatting."""
        from create_folder import format_human_readable

        folder_info = {
            'id': 'folder123',
            'name': 'Test Folder',
            'mimeType': 'application/vnd.google-apps.folder',
            'createdTime': '2025-12-20T10:30:00.000Z',
            'webViewLink': 'https://drive.google.com/drive/folders/folder123'
        }

        output = format_human_readable(folder_info)

        assert 'FOLDER CREATED SUCCESSFULLY' in output
        assert 'Test Folder' in output
        assert 'folder123' in output
        assert '2025-12-20T10:30:00.000Z' in output

    def test_format_folder_with_parent(self):
        """Test formatting folder with parent."""
        from create_folder import format_human_readable

        folder_info = {
            'id': 'folder456',
            'name': 'Subfolder',
            'parents': ['parent789']
        }

        output = format_human_readable(folder_info)

        assert 'Parent Folder: parent789' in output

    def test_format_folder_without_parent(self):
        """Test formatting folder in root."""
        from create_folder import format_human_readable

        folder_info = {
            'id': 'folder789',
            'name': 'Root Folder'
        }

        output = format_human_readable(folder_info)

        assert 'root (My Drive)' in output

    def test_format_folder_with_description(self):
        """Test formatting folder with description."""
        from create_folder import format_human_readable

        folder_info = {
            'id': 'folder111',
            'name': 'Archive',
            'description': 'Old project files'
        }

        output = format_human_readable(folder_info)

        assert 'Description: Old project files' in output


class TestMainFunction:
    """Test the main CLI function."""

    @patch('create_folder.get_drive_service')
    def test_main_success_json(self, mock_get_service, mock_drive_service, capsys):
        """Test successful folder creation via main function with JSON output."""
        from create_folder import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder123',
            'name': 'Test Folder',
            'mimeType': 'application/vnd.google-apps.folder'
        }

        with patch('sys.argv', ['create_folder.py', 'Test Folder', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert '"success": true' in captured.out
        assert '"Test Folder"' in captured.out

    @patch('create_folder.get_drive_service')
    def test_main_success_human_readable(self, mock_get_service, mock_drive_service, capsys):
        """Test successful folder creation with human-readable output."""
        from create_folder import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder456',
            'name': 'My Folder',
            'mimeType': 'application/vnd.google-apps.folder'
        }

        with patch('sys.argv', ['create_folder.py', 'My Folder']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert 'FOLDER CREATED SUCCESSFULLY' in captured.out
        assert 'My Folder' in captured.out

    @patch('create_folder.get_drive_service')
    def test_main_with_parent_id(self, mock_get_service, mock_drive_service, capsys):
        """Test folder creation with parent ID."""
        from create_folder import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder789',
            'name': 'Subfolder',
            'parents': ['parent123']
        }

        with patch('sys.argv', ['create_folder.py', 'Subfolder', '--parent-id', 'parent123', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

    @patch('create_folder.get_drive_service')
    def test_main_with_description(self, mock_get_service, mock_drive_service, capsys):
        """Test folder creation with description."""
        from create_folder import main

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().create().execute.return_value = {
            'id': 'folder111',
            'name': 'Archive',
            'description': 'Old files'
        }

        with patch('sys.argv', ['create_folder.py', 'Archive', '--description', 'Old files', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

    @patch('create_folder.get_drive_service')
    def test_main_auth_error(self, mock_get_service, capsys):
        """Test main function with authentication error."""
        from create_folder import main
        from gdrive_auth import DriveAuthError

        mock_get_service.side_effect = DriveAuthError("Auth failed")

        with patch('sys.argv', ['create_folder.py', 'Test', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert 'AuthenticationError' in captured.err
