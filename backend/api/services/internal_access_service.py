"""Internal-only capability access checks."""

from __future__ import annotations

from api.config import settings


class InternalAccessService:
    """Central authorization boundary for internal diagnostics features."""

    @staticmethod
    def can_access_internal_diagnostics(user_id: str) -> bool:
        """Return True when the given user may access notification diagnostics."""
        normalized_user_id = user_id.strip()
        if not normalized_user_id or not settings.runtime_internal_diagnostics_enabled:
            return False

        allowlisted_user_ids = {
            candidate.strip()
            for candidate in settings.runtime_internal_diagnostic_user_ids_raw.split(
                ","
            )
            if candidate.strip()
        }
        return normalized_user_id in allowlisted_user_ids
