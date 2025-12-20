"""
Tests for drive-write/scripts/upload_file.py
"""

import pytest
import sys
import os
import tempfile
from pathlib import Path
from unittest.mock import patch, MagicMock, Mock
from googleapiclient.errors import HttpError

# Add drive-write scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_write_scripts = project_root / "skills" / "drive-write" / "scripts"
sys.path.insert(0, str(drive_write_scripts))


class TestDetectMimeType:
    """Test MIME type detection."""

    def test_detect_pdf(self):
        """Test PDF MIME type detection."""
        from upload_file import detect_mime_type

        mime_type = detect_mime_type("document.pdf")
        assert mime_type == "application/pdf"

    def test_detect_text(self):
        """Test text file MIME type detection."""
        from upload_file import detect_mime_type

        mime_type = detect_mime_type("file.txt")
        assert mime_type == "text/plain"

    def test_detect_jpeg(self):
        """Test JPEG image MIME type detection."""
        from upload_file import detect_mime_type

        mime_type = detect_mime_type("image.jpg")
        assert mime_type == "image/jpeg"

    def test_detect_unknown(self):
        """Test unknown file extension."""
        from upload_file import detect_mime_type

        mime_type = detect_mime_type("file.unknownext")
        assert mime_type == "application/octet-stream"


class TestUploadFile:
    """Test file upload functionality."""

    def test_upload_file_basic(self, mock_drive_service, tmp_path):
        """Test basic file upload."""
        from upload_file import upload_file

        # Create a temporary file
        test_file = tmp_path / "test.txt"
        test_file.write_text("test content")

        mock_drive_service.files().create().execute.return_value = {
            'id': '123',
            'name': 'test.txt',
            'mimeType': 'text/plain',
            'size': '12'
        }

        result = upload_file(
            mock_drive_service,
            file_path=str(test_file)
        )

        assert result['id'] == '123'
        assert result['name'] == 'test.txt'

    def test_upload_file_with_custom_name(self, mock_drive_service, tmp_path):
        """Test upload with custom name."""
        from upload_file import upload_file

        test_file = tmp_path / "original.txt"
        test_file.write_text("content")

        mock_drive_service.files().create().execute.return_value = {
            'id': '456',
            'name': 'custom_name.txt'
        }

        result = upload_file(
            mock_drive_service,
            file_path=str(test_file),
            name='custom_name.txt'
        )

        # Verify custom name was used
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['name'] == 'custom_name.txt'

    def test_upload_file_with_parent(self, mock_drive_service, tmp_path):
        """Test upload to specific folder."""
        from upload_file import upload_file

        test_file = tmp_path / "test.txt"
        test_file.write_text("content")

        mock_drive_service.files().create().execute.return_value = {
            'id': '789',
            'parents': ['parent123']
        }

        result = upload_file(
            mock_drive_service,
            file_path=str(test_file),
            parent_id='parent123'
        )

        # Verify parent was set
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['parents'] == ['parent123']

    def test_upload_file_with_mime_type(self, mock_drive_service, tmp_path):
        """Test upload with explicit MIME type."""
        from upload_file import upload_file

        test_file = tmp_path / "data.csv"
        test_file.write_text("col1,col2\n1,2")

        mock_drive_service.files().create().execute.return_value = {
            'id': '111',
            'mimeType': 'text/csv'
        }

        result = upload_file(
            mock_drive_service,
            file_path=str(test_file),
            mime_type='text/csv'
        )

        # Verify MIME type was used
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['mimeType'] == 'text/csv'

    def test_upload_file_with_description(self, mock_drive_service, tmp_path):
        """Test upload with description."""
        from upload_file import upload_file

        test_file = tmp_path / "test.txt"
        test_file.write_text("content")

        mock_drive_service.files().create().execute.return_value = {
            'id': '222',
            'description': 'Test description'
        }

        result = upload_file(
            mock_drive_service,
            file_path=str(test_file),
            description='Test description'
        )

        # Verify description was set
        call_args = mock_drive_service.files().create.call_args
        assert call_args[1]['body']['description'] == 'Test description'

    def test_upload_file_not_found(self, mock_drive_service):
        """Test upload with non-existent file."""
        from upload_file import upload_file
        from gdrive_retry import PermanentError

        with pytest.raises(PermanentError, match="File not found"):
            upload_file(
                mock_drive_service,
                file_path='/nonexistent/file.txt'
            )

    def test_upload_file_uses_resumable_for_large_files(self, mock_drive_service, tmp_path):
        """Test that resumable upload is used for large files."""
        from upload_file import upload_file, RESUMABLE_THRESHOLD

        # Create a file larger than the threshold
        test_file = tmp_path / "large.bin"
        test_file.write_bytes(b'x' * (RESUMABLE_THRESHOLD + 1))

        mock_drive_service.files().create().execute.return_value = {
            'id': '333',
            'name': 'large.bin'
        }

        with patch('upload_file.MediaFileUpload') as mock_media:
            result = upload_file(
                mock_drive_service,
                file_path=str(test_file)
            )

            # Verify MediaFileUpload was called with resumable=True
            mock_media.assert_called_once()
            call_kwargs = mock_media.call_args[1]
            assert call_kwargs['resumable'] is True

    def test_upload_file_uses_simple_for_small_files(self, mock_drive_service, tmp_path):
        """Test that simple upload is used for small files."""
        from upload_file import upload_file, RESUMABLE_THRESHOLD

        # Create a small file
        test_file = tmp_path / "small.txt"
        test_file.write_bytes(b'small content')

        mock_drive_service.files().create().execute.return_value = {
            'id': '444',
            'name': 'small.txt'
        }

        with patch('upload_file.MediaFileUpload') as mock_media:
            result = upload_file(
                mock_drive_service,
                file_path=str(test_file)
            )

            # Verify MediaFileUpload was called with resumable=False
            mock_media.assert_called_once()
            call_kwargs = mock_media.call_args[1]
            assert call_kwargs['resumable'] is False


class TestFormatFileSize:
    """Test file size formatting."""

    def test_format_bytes(self):
        """Test formatting bytes."""
        from upload_file import format_file_size

        assert format_file_size(512) == "512 B"

    def test_format_kilobytes(self):
        """Test formatting kilobytes."""
        from upload_file import format_file_size

        assert format_file_size(1024) == "1.00 KB"
        assert format_file_size(2048) == "2.00 KB"

    def test_format_megabytes(self):
        """Test formatting megabytes."""
        from upload_file import format_file_size

        assert format_file_size(1024 * 1024) == "1.00 MB"
        assert format_file_size(5 * 1024 * 1024) == "5.00 MB"

    def test_format_gigabytes(self):
        """Test formatting gigabytes."""
        from upload_file import format_file_size

        assert format_file_size(1024 * 1024 * 1024) == "1.00 GB"


class TestFormatHumanReadable:
    """Test human-readable output formatting."""

    def test_format_basic(self, tmp_path):
        """Test basic formatting."""
        from upload_file import format_human_readable

        test_file = tmp_path / "test.txt"
        test_file.write_text("content")

        file_info = {
            'id': '123',
            'name': 'test.txt',
            'mimeType': 'text/plain',
            'size': '1024',
            'webViewLink': 'https://drive.google.com/file/d/123/view'
        }

        output = format_human_readable(file_info, str(test_file))

        assert 'FILE UPLOADED SUCCESSFULLY' in output
        assert 'test.txt' in output
        assert '123' in output
        assert 'text/plain' in output


class TestMainFunction:
    """Test the main CLI function."""

    @patch('upload_file.get_drive_service')
    def test_main_success(self, mock_get_service, mock_drive_service, capsys, tmp_path):
        """Test successful upload via main function."""
        from upload_file import main

        test_file = tmp_path / "test.txt"
        test_file.write_text("content")

        mock_get_service.return_value = mock_drive_service
        mock_drive_service.files().create().execute.return_value = {
            'id': '123',
            'name': 'test.txt',
            'mimeType': 'text/plain',
            'size': '7'
        }

        with patch('sys.argv', ['upload_file.py', str(test_file), '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert '"success": true' in captured.out

    @patch('upload_file.get_drive_service')
    def test_main_file_not_found(self, mock_get_service, capsys):
        """Test main function with non-existent file."""
        from upload_file import main

        with patch('sys.argv', ['upload_file.py', '/nonexistent/file.txt', '--json']):
            with pytest.raises(SystemExit) as exc_info:
                main()

        assert exc_info.value.code == 1

        captured = capsys.readouterr()
        assert 'FileNotFoundError' in captured.err
