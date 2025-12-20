"""
Tests for Google Drive retry logic (gdrive_retry.py)
"""

import pytest
import sys
from pathlib import Path
from unittest.mock import patch, Mock
from googleapiclient.errors import HttpError

# Add drive-read scripts to path
project_root = Path(__file__).parent.parent.parent.parent
drive_read_scripts = project_root / "skills" / "drive-read" / "scripts"
sys.path.insert(0, str(drive_read_scripts))


class TestIsRetryableError:
    """Test error categorization."""

    def test_rate_limit_429_is_retryable(self):
        """Test that 429 rate limit errors are retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=429),
            content=b'{"error": {"message": "Too many requests"}}'
        )

        assert is_retryable_error(error) is True

    def test_server_error_500_is_retryable(self):
        """Test that 500 server errors are retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=500),
            content=b'{"error": {"message": "Internal server error"}}'
        )

        assert is_retryable_error(error) is True

    def test_server_error_503_is_retryable(self):
        """Test that 503 service unavailable errors are retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=503),
            content=b'{"error": {"message": "Service unavailable"}}'
        )

        assert is_retryable_error(error) is True

    def test_not_found_404_is_not_retryable(self):
        """Test that 404 not found errors are not retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=404),
            content=b'{"error": {"message": "File not found"}}'
        )

        assert is_retryable_error(error) is False

    def test_unauthorized_401_is_not_retryable(self):
        """Test that 401 unauthorized errors are not retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=401),
            content=b'{"error": {"message": "Unauthorized"}}'
        )

        assert is_retryable_error(error) is False

    def test_forbidden_403_permission_is_not_retryable(self):
        """Test that 403 permission denied (non-rate-limit) is not retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=403),
            content=b'{"error": {"message": "Permission denied"}}'
        )
        error.error_details = [{'reason': 'permissionDenied'}]

        assert is_retryable_error(error) is False

    def test_forbidden_403_rate_limit_is_retryable(self):
        """Test that 403 rate limit errors are retryable."""
        from gdrive_retry import is_retryable_error

        error = HttpError(
            resp=Mock(status=403),
            content=b'{"error": {"message": "Rate limit exceeded"}}'
        )
        error.error_details = [{'reason': 'userRateLimitExceeded'}]

        assert is_retryable_error(error) is True


class TestExponentialBackoffRetry:
    """Test exponential backoff decorator."""

    @patch('time.sleep')
    def test_successful_call_no_retry(self, mock_sleep):
        """Test that successful calls don't trigger retries."""
        from gdrive_retry import exponential_backoff_retry

        @exponential_backoff_retry(max_retries=3)
        def successful_function():
            return "success"

        result = successful_function()

        assert result == "success"
        assert mock_sleep.call_count == 0

    @patch('time.sleep')
    def test_retry_on_transient_error(self, mock_sleep):
        """Test retry on transient errors."""
        from gdrive_retry import exponential_backoff_retry

        call_count = 0

        @exponential_backoff_retry(max_retries=3)
        def failing_then_succeeding():
            nonlocal call_count
            call_count += 1
            if call_count < 3:
                raise HttpError(
                    resp=Mock(status=429),
                    content=b'{"error": {}}'
                )
            return "success"

        result = failing_then_succeeding()

        assert result == "success"
        assert call_count == 3
        assert mock_sleep.call_count == 2  # Slept twice before success

    @patch('time.sleep')
    def test_permanent_error_no_retry(self, mock_sleep):
        """Test that permanent errors are not retried."""
        from gdrive_retry import exponential_backoff_retry, PermanentError

        @exponential_backoff_retry(max_retries=3)
        def permanent_failure():
            raise HttpError(
                resp=Mock(status=404),
                content=b'{"error": {"message": "Not found"}}'
            )

        with pytest.raises(PermanentError, match="API request failed"):
            permanent_failure()

        assert mock_sleep.call_count == 0  # No retries

    @patch('time.sleep')
    def test_max_retries_exceeded(self, mock_sleep):
        """Test that max retries is enforced."""
        from gdrive_retry import exponential_backoff_retry, RetryableError

        @exponential_backoff_retry(max_retries=2)
        def always_failing():
            raise HttpError(
                resp=Mock(status=429),
                content=b'{"error": {}}'
            )

        with pytest.raises(RetryableError, match="Max retries"):
            always_failing()

        # Should retry max_retries times
        assert mock_sleep.call_count == 2

    @patch('time.sleep')
    def test_exponential_backoff_timing(self, mock_sleep):
        """Test that backoff time increases exponentially."""
        from gdrive_retry import exponential_backoff_retry, RetryableError

        @exponential_backoff_retry(max_retries=3, base_wait=1, max_backoff=64)
        def always_failing():
            raise HttpError(
                resp=Mock(status=429),
                content=b'{"error": {}}'
            )

        with pytest.raises(RetryableError):
            always_failing()

        # Verify exponential backoff was applied
        assert mock_sleep.call_count == 3

        # Check that wait times increase (approximately 2^n)
        wait_times = [call[0][0] for call in mock_sleep.call_args_list]
        assert wait_times[0] >= 2  # 2^1 + jitter
        assert wait_times[1] >= 4  # 2^2 + jitter
        assert wait_times[2] >= 8  # 2^3 + jitter


class TestRetryContext:
    """Test RetryContext manager."""

    @patch('time.sleep')
    def test_retry_context_basic_usage(self, mock_sleep):
        """Test RetryContext for manual retry logic."""
        from gdrive_retry import RetryContext

        retry_ctx = RetryContext(max_retries=3)
        error = HttpError(resp=Mock(status=429), content=b'{}')

        # First retry should return True
        assert retry_ctx.should_retry(error) is True
        assert retry_ctx.retry_count == 1

        # Second retry should return True
        assert retry_ctx.should_retry(error) is True
        assert retry_ctx.retry_count == 2

        # Third retry should return True
        assert retry_ctx.should_retry(error) is True
        assert retry_ctx.retry_count == 3

        # Fourth retry should return False (exceeded max)
        assert retry_ctx.should_retry(error) is False

        assert mock_sleep.call_count == 3

    def test_retry_context_permanent_error(self):
        """Test RetryContext with permanent error."""
        from gdrive_retry import RetryContext

        retry_ctx = RetryContext(max_retries=3)
        error = HttpError(resp=Mock(status=404), content=b'{}')

        # Permanent error should not be retried
        assert retry_ctx.should_retry(error) is False
        assert retry_ctx.retry_count == 0
