#!/usr/bin/env python3
"""
Retry logic with exponential backoff for Google Drive API calls.

Implements the recommended retry strategy from Google Drive API documentation:
https://developers.google.com/workspace/drive/api/guides/limits
"""

import sys
import time
import random
from functools import wraps
from googleapiclient.errors import HttpError


class RetryableError(Exception):
    """Error that should be retried with exponential backoff."""
    pass


class PermanentError(Exception):
    """Error that should not be retried."""
    pass


# HTTP status codes that indicate transient errors
RETRYABLE_STATUS_CODES = {429, 500, 503}

# Error reasons that are retryable even if status is 403
RETRYABLE_REASONS = {'userRateLimitExceeded', 'rateLimitExceeded'}


def is_retryable_error(error: HttpError) -> bool:
    """
    Determine if an HttpError should be retried.

    Args:
        error: HttpError from Google API client

    Returns:
        bool: True if error is transient and should be retried
    """
    status_code = error.resp.status

    # Check if status code is retryable
    if status_code in RETRYABLE_STATUS_CODES:
        return True

    # For 403, check if it's actually a rate limit error
    if status_code == 403:
        try:
            error_details = error.error_details
            for detail in error_details:
                if detail.get('reason') in RETRYABLE_REASONS:
                    return True
        except:
            pass

    return False


def exponential_backoff_retry(max_retries=5, max_backoff=64, base_wait=1):
    """
    Decorator that implements exponential backoff retry logic.

    Formula: wait_time = min((2^n + random_jitter), max_backoff)
    where n is the retry attempt number and random_jitter is 0-1 seconds.

    Args:
        max_retries: Maximum number of retry attempts (default: 5)
        max_backoff: Maximum wait time in seconds (default: 64)
        base_wait: Base wait time in seconds (default: 1)

    Example:
        @exponential_backoff_retry(max_retries=3)
        def list_files(service):
            return service.files().list().execute()
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            retry_count = 0

            while True:
                try:
                    return func(*args, **kwargs)

                except HttpError as e:
                    retry_count += 1

                    # Check if error is retryable
                    if not is_retryable_error(e):
                        # Permanent error - raise immediately
                        error_msg = str(e)
                        try:
                            if hasattr(e, 'error_details'):
                                error_msg = f"{e.resp.status} - {e.error_details}"
                        except:
                            pass
                        raise PermanentError(f"API request failed: {error_msg}") from e

                    # Check if we've exhausted retries
                    if retry_count > max_retries:
                        error_msg = str(e)
                        try:
                            if hasattr(e, 'error_details'):
                                error_msg = f"{e.resp.status} - {e.error_details}"
                        except:
                            pass
                        raise RetryableError(
                            f"Max retries ({max_retries}) exceeded. Last error: {error_msg}"
                        ) from e

                    # Calculate wait time with exponential backoff
                    wait_time = min(
                        (2 ** retry_count) * base_wait + random.random(),
                        max_backoff
                    )

                    print(
                        f"⚠️  Rate limit or transient error (attempt {retry_count}/{max_retries}). "
                        f"Retrying in {wait_time:.1f}s...",
                        file=sys.stderr
                    )

                    time.sleep(wait_time)

                except Exception as e:
                    # Non-HTTP error - raise as permanent
                    raise PermanentError(f"Unexpected error: {e}") from e

        return wrapper
    return decorator


class RetryContext:
    """
    Context manager for manual retry logic.

    Example:
        retry_ctx = RetryContext(max_retries=3)
        while True:
            try:
                result = service.files().list().execute()
                break
            except HttpError as e:
                if not retry_ctx.should_retry(e):
                    raise
    """

    def __init__(self, max_retries=5, max_backoff=64, base_wait=1):
        self.max_retries = max_retries
        self.max_backoff = max_backoff
        self.base_wait = base_wait
        self.retry_count = 0

    def should_retry(self, error: HttpError) -> bool:
        """
        Check if should retry and handle wait time.

        Args:
            error: HttpError from Google API client

        Returns:
            bool: True if should retry, False if should give up
        """
        if not is_retryable_error(error):
            return False

        self.retry_count += 1

        if self.retry_count > self.max_retries:
            return False

        wait_time = min(
            (2 ** self.retry_count) * self.base_wait + random.random(),
            self.max_backoff
        )

        print(
            f"⚠️  Retrying (attempt {self.retry_count}/{self.max_retries}) "
            f"in {wait_time:.1f}s...",
            file=sys.stderr
        )

        time.sleep(wait_time)
        return True
