"""
Tests for Google Drive authentication (gdrive_auth.py)
"""

import pytest
import sys
import json
from pathlib import Path
from unittest.mock import patch, MagicMock

# Add drive-read scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_read_scripts = project_root / "skills" / "drive-read" / "scripts"
sys.path.insert(0, str(drive_read_scripts))


class TestDriveAuthentication:
    """Test Google Drive authentication functionality."""

    def test_get_drive_service_success(self, mock_env_vars):
        """Test successful authentication with service account JSON."""
        with patch('gdrive_auth.service_account.Credentials.from_service_account_info') as mock_creds:
            with patch('gdrive_auth.build') as mock_build:
                from gdrive_auth import get_drive_service

                mock_creds.return_value = MagicMock()
                mock_build.return_value = MagicMock()

                service = get_drive_service()

                # Verify credentials were created
                assert mock_creds.called
                # Verify service was built
                assert mock_build.called
                assert mock_build.call_args[0] == ('drive', 'v3')

    def test_get_drive_service_missing_env_var(self, monkeypatch):
        """Test authentication failure when environment variable is missing."""
        # Remove the environment variable
        monkeypatch.delenv('GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON', raising=False)

        from gdrive_auth import get_drive_service, DriveAuthError

        with pytest.raises(DriveAuthError, match="environment variable not set"):
            get_drive_service()

    def test_get_drive_service_invalid_json(self, monkeypatch):
        """Test authentication failure with invalid JSON."""
        monkeypatch.setenv('GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON', 'not valid json')

        from gdrive_auth import get_drive_service, DriveAuthError

        with pytest.raises(DriveAuthError, match="Failed to parse"):
            get_drive_service()

    def test_get_drive_service_custom_api_version(self, mock_env_vars):
        """Test authentication with custom API version."""
        with patch('gdrive_auth.service_account.Credentials.from_service_account_info') as mock_creds:
            with patch('gdrive_auth.build') as mock_build:
                from gdrive_auth import get_drive_service

                mock_creds.return_value = MagicMock()
                mock_build.return_value = MagicMock()

                service = get_drive_service(api_version='v2')

                assert mock_build.call_args[0] == ('drive', 'v2')


class TestDriveAuthError:
    """Test DriveAuthError exception."""

    def test_drive_auth_error_message(self):
        """Test DriveAuthError can be created with custom message."""
        from gdrive_auth import DriveAuthError

        error = DriveAuthError("Custom error message")
        assert str(error) == "Custom error message"
