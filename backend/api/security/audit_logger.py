"""Structured audit logging for all tool calls."""

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger("sidebar.audit")


class AuditLogger:
    """Log all tool calls with structured data for audit trails."""

    @staticmethod
    def log_tool_call(
        tool_name: str,
        parameters: dict[str, Any],
        resolved_path: Path | None = None,
        duration_ms: float | None = None,
        success: bool = True,
        error: str | None = None,
        user_id: str | None = None,
    ):
        """Log a tool call with all relevant metadata."""
        # Redact secrets from parameters
        safe_params = AuditLogger._redact_secrets(parameters)

        audit_entry = {
            "timestamp": datetime.utcnow().isoformat(),
            "tool_name": tool_name,
            "parameters": safe_params,
            "resolved_path": str(resolved_path) if resolved_path else None,
            "duration_ms": duration_ms,
            "success": success,
            "error": error,
            "user_id": user_id,
        }

        if success:
            logger.info(f"TOOL_CALL: {json.dumps(audit_entry)}")
        else:
            logger.error(f"TOOL_CALL_FAILED: {json.dumps(audit_entry)}")

    @staticmethod
    def _redact_secrets(params: dict[str, Any]) -> dict[str, Any]:
        """Redact sensitive values from parameters."""
        redacted = {}
        secret_keys = {"password", "token", "api_key", "secret", "credential"}

        for key, value in params.items():
            if any(secret in key.lower() for secret in secret_keys):
                redacted[key] = "[REDACTED]"
            elif isinstance(value, str) and len(value) > 100:
                # Truncate very long strings
                redacted[key] = value[:100] + "...[truncated]"
            else:
                redacted[key] = value

        return redacted
