"""Custom exception hierarchy for API errors."""
from __future__ import annotations

from typing import Any, Dict, Optional


class APIError(Exception):
    """Base exception for API errors."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or {}
        super().__init__(message)


class BadRequestError(APIError):
    """Request validation failed."""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None) -> None:
        super().__init__(400, "BAD_REQUEST", message, details)


class ValidationError(APIError):
    """Input validation failed."""

    def __init__(self, field: str, message: str) -> None:
        super().__init__(
            400,
            "VALIDATION_ERROR",
            f"Validation failed for field '{field}': {message}",
            {"field": field},
        )


class AuthenticationError(APIError):
    """Authentication failed."""

    def __init__(self, message: str = "Authentication required") -> None:
        super().__init__(401, "AUTHENTICATION_REQUIRED", message)


class InvalidTokenError(APIError):
    """Invalid or expired token."""

    def __init__(self, message: str = "Invalid or expired token") -> None:
        super().__init__(401, "INVALID_TOKEN", message)


class PermissionDeniedError(APIError):
    """User lacks permission for this action."""

    def __init__(self, resource: str, action: str = "access") -> None:
        super().__init__(
            403,
            "PERMISSION_DENIED",
            f"Permission denied to {action} {resource}",
            {"resource": resource, "action": action},
        )


class NotFoundError(APIError):
    """Resource not found."""

    def __init__(self, resource: str, identifier: str) -> None:
        super().__init__(
            404,
            "NOT_FOUND",
            f"{resource} not found: {identifier}",
            {"resource": resource, "identifier": identifier},
        )


class NoteNotFoundError(NotFoundError):
    """Note not found."""

    def __init__(self, note_id: str) -> None:
        super().__init__("Note", note_id)


class WebsiteNotFoundError(NotFoundError):
    """Website not found."""

    def __init__(self, website_id: str) -> None:
        super().__init__("Website", website_id)


class ConversationNotFoundError(NotFoundError):
    """Conversation not found."""

    def __init__(self, conversation_id: str) -> None:
        super().__init__("Conversation", conversation_id)


class FileNotFoundError(NotFoundError):
    """File not found."""

    def __init__(self, file_path: str) -> None:
        super().__init__("File", file_path)


class ConflictError(APIError):
    """Resource conflict."""

    def __init__(self, message: str, details: Optional[Dict[str, Any]] = None) -> None:
        super().__init__(409, "CONFLICT", message, details)


class PayloadTooLargeError(APIError):
    """Payload too large."""

    def __init__(self, message: str = "Payload too large") -> None:
        super().__init__(413, "PAYLOAD_TOO_LARGE", message)


class RangeNotSatisfiableError(APIError):
    """Requested range is not satisfiable."""

    def __init__(self, message: str = "Invalid range") -> None:
        super().__init__(416, "RANGE_NOT_SATISFIABLE", message)


class ServiceUnavailableError(APIError):
    """Service temporarily unavailable."""

    def __init__(self, message: str = "Service unavailable") -> None:
        super().__init__(503, "SERVICE_UNAVAILABLE", message)


class InternalServerError(APIError):
    """Internal server error."""

    def __init__(self, message: str = "An internal error occurred") -> None:
        super().__init__(500, "INTERNAL_ERROR", message)


class ExternalServiceError(APIError):
    """External service error."""

    def __init__(self, service: str, message: str) -> None:
        super().__init__(
            502,
            "EXTERNAL_SERVICE_ERROR",
            f"Error from {service}: {message}",
            {"service": service},
        )
