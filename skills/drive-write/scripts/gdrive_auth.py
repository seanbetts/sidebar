#!/usr/bin/env python3
"""
Shared Google Drive authentication module using Service Account credentials.

This module handles authentication for all Google Drive skills using a Service
Account JSON key stored in Doppler secrets.

Environment Variables:
    GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON: Complete JSON key as string

Usage:
    from gdrive_auth import get_drive_service

    service = get_drive_service()
    results = service.files().list(pageSize=10).execute()
"""

import os
import sys
import json
from typing import Optional
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError


# Google Drive API scopes
SCOPES = ['https://www.googleapis.com/auth/drive']


class DriveAuthError(Exception):
    """Custom exception for Drive authentication errors."""
    pass


def get_drive_service(api_version: str = 'v3'):
    """
    Create and return an authenticated Google Drive service object.

    Args:
        api_version: Google Drive API version (default: 'v3')

    Returns:
        Resource: Authenticated Google Drive service object

    Raises:
        DriveAuthError: If authentication fails

    Example:
        >>> service = get_drive_service()
        >>> results = service.files().list(pageSize=10).execute()
    """
    try:
        # Get service account JSON from environment
        service_account_json = os.environ.get('GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON')

        if not service_account_json:
            raise DriveAuthError(
                "GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON environment variable not set. "
                "Please configure the service account credentials in Doppler."
            )

        # Parse JSON credentials
        try:
            credentials_dict = json.loads(service_account_json)
        except json.JSONDecodeError as e:
            raise DriveAuthError(
                f"Failed to parse GOOGLE_DRIVE_SERVICE_ACCOUNT_JSON: {e}"
            )

        # Create credentials from the parsed dictionary
        credentials = service_account.Credentials.from_service_account_info(
            credentials_dict,
            scopes=SCOPES
        )

        # Build and return the service
        service = build('drive', api_version, credentials=credentials)
        return service

    except DriveAuthError:
        raise
    except Exception as e:
        raise DriveAuthError(f"Unexpected error during authentication: {e}")


def get_drive_service_from_file(key_file_path: str, api_version: str = 'v3'):
    """
    Alternative: Create service from a local JSON key file.

    This is useful for local testing without Doppler.

    Args:
        key_file_path: Path to service account JSON key file
        api_version: Google Drive API version (default: 'v3')

    Returns:
        Resource: Authenticated Google Drive service object

    Raises:
        DriveAuthError: If authentication fails
    """
    try:
        if not Path(key_file_path).exists():
            raise DriveAuthError(f"Key file not found: {key_file_path}")

        credentials = service_account.Credentials.from_service_account_file(
            key_file_path,
            scopes=SCOPES
        )

        service = build('drive', api_version, credentials=credentials)
        return service

    except DriveAuthError:
        raise
    except Exception as e:
        raise DriveAuthError(f"Failed to authenticate from file: {e}")


if __name__ == '__main__':
    # Test authentication
    try:
        service = get_drive_service()
        print("✅ Authentication successful!")

        # Test API call
        results = service.about().get(fields="user").execute()
        user_email = results.get('user', {}).get('emailAddress', 'Unknown')
        print(f"✅ Authenticated as: {user_email}")

    except DriveAuthError as e:
        print(f"❌ Authentication failed: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)
