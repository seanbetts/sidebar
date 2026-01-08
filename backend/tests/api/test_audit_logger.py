"""Tests for AuditLogger."""

import logging
from pathlib import Path

import pytest
from api.security.audit_logger import AuditLogger


@pytest.fixture
def capture_logs(caplog):
    """Capture audit logs."""
    caplog.set_level(logging.INFO, logger="sidebar.audit")
    return caplog


class TestAuditLogger:
    """Test audit logging functionality."""

    def test_log_successful_tool_call(self, capture_logs):
        """Should log successful tool calls."""
        AuditLogger.log_tool_call(
            tool_name="fs_list",
            parameters={"path": ".", "pattern": "*.txt"},
            resolved_path=Path("/tmp/skills/documents"),
            duration_ms=125.5,
            success=True,
        )

        assert len(capture_logs.records) == 1
        record = capture_logs.records[0]

        assert record.levelname == "INFO"
        assert "TOOL_CALL" in record.message
        assert "fs_list" in record.message
        assert "125.5" in record.message

    def test_log_failed_tool_call(self, capture_logs):
        """Should log failed tool calls."""
        AuditLogger.log_tool_call(
            tool_name="fs_write",
            parameters={"path": "test.txt"},
            duration_ms=50.0,
            success=False,
            error="Permission denied",
        )

        assert len(capture_logs.records) == 1
        record = capture_logs.records[0]

        assert record.levelname == "ERROR"
        assert "TOOL_CALL_FAILED" in record.message
        assert "fs_write" in record.message
        assert "Permission denied" in record.message

    def test_redact_secrets_from_parameters(self, capture_logs):
        """Should redact sensitive parameters."""
        AuditLogger.log_tool_call(
            tool_name="api_call",
            parameters={
                "url": "https://example.com",
                "api_key": "secret-key-12345",
                "password": "super-secret",
                "token": "bearer-token",
                "data": "normal data",
            },
            success=True,
        )

        record = capture_logs.records[0]
        message = record.message

        # Secrets should be redacted
        assert "secret-key-12345" not in message
        assert "super-secret" not in message
        assert "bearer-token" not in message
        assert "[REDACTED]" in message

        # Normal data should be preserved
        assert "normal data" in message
        assert "https://example.com" in message

    def test_truncate_long_strings(self, capture_logs):
        """Should truncate very long parameter values."""
        long_content = "x" * 200

        AuditLogger.log_tool_call(
            tool_name="fs_write", parameters={"content": long_content}, success=True
        )

        record = capture_logs.records[0]
        message = record.message

        # Should be truncated
        assert "[truncated]" in message
        assert len(long_content) > 100  # Original is long
        # Truncated version should be shorter
        assert message.count("x") < 150

    def test_log_with_user_id(self, capture_logs):
        """Should include user ID when provided."""
        AuditLogger.log_tool_call(
            tool_name="fs_delete",
            parameters={"path": "old-file.txt"},
            success=True,
            user_id="user-123",
        )

        record = capture_logs.records[0]
        assert "user-123" in record.message

    def test_log_without_optional_fields(self, capture_logs):
        """Should handle missing optional fields."""
        AuditLogger.log_tool_call(tool_name="simple_tool", parameters={}, success=True)

        # Should not raise exception
        assert len(capture_logs.records) == 1

    def test_log_structured_json_format(self, capture_logs):
        """Should log in structured JSON format."""
        import json

        AuditLogger.log_tool_call(
            tool_name="test_tool",
            parameters={"key": "value"},
            resolved_path=Path("/tmp/skills/test"),
            duration_ms=100.0,
            success=True,
            user_id="user-1",
        )

        record = capture_logs.records[0]
        message = record.message

        # Should contain JSON after "TOOL_CALL: "
        json_start = message.index("{")
        json_str = message[json_start:]
        data = json.loads(json_str)

        # Verify structure
        assert data["tool_name"] == "test_tool"
        assert data["parameters"] == {"key": "value"}
        assert data["resolved_path"] == "/tmp/skills/test"
        assert data["duration_ms"] == 100.0
        assert data["success"] is True
        assert data["user_id"] == "user-1"
        assert "timestamp" in data


class TestAuditLoggerEdgeCases:
    """Test edge cases in audit logging."""

    def test_redact_nested_secrets(self, capture_logs):
        """Should handle nested dictionaries (flatten for now)."""
        AuditLogger.log_tool_call(
            tool_name="test",
            parameters={"config": {"api_key": "secret", "url": "https://example.com"}},
            success=True,
        )

        # Should not crash
        assert len(capture_logs.records) == 1

    def test_handle_none_values(self, capture_logs):
        """Should handle None values in parameters."""
        AuditLogger.log_tool_call(
            tool_name="test",
            parameters={"optional_field": None},
            success=True,
            error=None,
            user_id=None,
            resolved_path=None,
        )

        assert len(capture_logs.records) == 1

    def test_handle_special_characters_in_params(self, capture_logs):
        """Should handle special characters in parameters."""
        AuditLogger.log_tool_call(
            tool_name="test",
            parameters={
                "path": "file with spaces & special-chars.txt",
                "content": "Line 1\nLine 2\tTabbed",
            },
            success=True,
        )

        record = capture_logs.records[0]
        # Should not crash and should be valid JSON
        import json

        json_start = record.message.index("{")
        data = json.loads(record.message[json_start:])
        assert data["parameters"]["path"] == "file with spaces & special-chars.txt"
