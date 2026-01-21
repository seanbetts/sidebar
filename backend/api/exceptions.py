"""Custom exception hierarchy for API errors."""

from __future__ import annotations

from typing import Any


class APIError(Exception):
    """Base exception for API errors."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
    ) -> None:
        """Initialize an API error with metadata for responses."""
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or {}
        super().__init__(message)


class BadRequestError(APIError):
    """Request validation failed."""

    def __init__(self, message: str, details: dict[str, Any] | None = None) -> None:
        """Initialize a bad request error."""
        super().__init__(400, "BAD_REQUEST", message, details)


class ValidationError(APIError):
    """Input validation failed."""

    def __init__(self, field: str, message: str) -> None:
        """Initialize a validation error for a specific field."""
        super().__init__(
            400,
            "VALIDATION_ERROR",
            f"Validation failed for field '{field}': {message}",
            {"field": field},
        )


class AuthenticationError(APIError):
    """Authentication failed."""

    def __init__(self, message: str = "Authentication required") -> None:
        """Initialize an authentication error."""
        super().__init__(401, "AUTHENTICATION_REQUIRED", message)


class InvalidTokenError(APIError):
    """Invalid or expired token."""

    def __init__(self, message: str = "Invalid or expired token") -> None:
        """Initialize an invalid token error."""
        super().__init__(401, "INVALID_TOKEN", message)


class PermissionDeniedError(APIError):
    """User lacks permission for this action."""

    def __init__(self, resource: str, action: str = "access") -> None:
        """Initialize a permission denied error."""
        super().__init__(
            403,
            "PERMISSION_DENIED",
            f"Permission denied to {action} {resource}",
            {"resource": resource, "action": action},
        )


class NotFoundError(APIError):
    """Resource not found."""

    def __init__(self, resource: str, identifier: str) -> None:
        """Initialize a not found error for a resource."""
        super().__init__(
            404,
            "NOT_FOUND",
            f"{resource} not found: {identifier}",
            {"resource": resource, "identifier": identifier},
        )


class NoteNotFoundError(NotFoundError):
    """Note not found."""

    def __init__(self, note_id: str) -> None:
        """Initialize a not found error for a note."""
        super().__init__("Note", note_id)


class WebsiteNotFoundError(NotFoundError):
    """Website not found."""

    def __init__(self, website_id: str) -> None:
        """Initialize a not found error for a website."""
        super().__init__("Website", website_id)


class ConversationNotFoundError(NotFoundError):
    """Conversation not found."""

    def __init__(self, conversation_id: str) -> None:
        """Initialize a not found error for a conversation."""
        super().__init__("Conversation", conversation_id)


class TaskNotFoundError(NotFoundError):
    """Task not found."""

    def __init__(self, task_id: str) -> None:
        """Initialize a not found error for a task."""
        super().__init__("Task", task_id)


class TaskAreaNotFoundError(NotFoundError):
    """Task area not found."""

    def __init__(self, area_id: str) -> None:
        """Initialize a not found error for a task area."""
        super().__init__("TaskArea", area_id)


class TaskProjectNotFoundError(NotFoundError):
    """Task project not found."""

    def __init__(self, project_id: str) -> None:
        """Initialize a not found error for a task project."""
        super().__init__("TaskProject", project_id)


class FileNotFoundError(NotFoundError):
    """File not found."""

    def __init__(self, file_path: str) -> None:
        """Initialize a not found error for a file."""
        super().__init__("File", file_path)


class ConflictError(APIError):
    """Resource conflict."""

    def __init__(self, message: str, details: dict[str, Any] | None = None) -> None:
        """Initialize a conflict error."""
        super().__init__(409, "CONFLICT", message, details)


class PayloadTooLargeError(APIError):
    """Payload too large."""

    def __init__(self, message: str = "Payload too large") -> None:
        """Initialize a payload too large error."""
        super().__init__(413, "PAYLOAD_TOO_LARGE", message)


class RangeNotSatisfiableError(APIError):
    """Requested range is not satisfiable."""

    def __init__(self, message: str = "Invalid range") -> None:
        """Initialize a range not satisfiable error."""
        super().__init__(416, "RANGE_NOT_SATISFIABLE", message)


class ServiceUnavailableError(APIError):
    """Service temporarily unavailable."""

    def __init__(self, message: str = "Service unavailable") -> None:
        """Initialize a service unavailable error."""
        super().__init__(503, "SERVICE_UNAVAILABLE", message)


class InternalServerError(APIError):
    """Internal server error."""

    def __init__(self, message: str = "An internal error occurred") -> None:
        """Initialize an internal server error."""
        super().__init__(500, "INTERNAL_ERROR", message)


class ExternalServiceError(APIError):
    """External service error."""

    def __init__(self, service: str, message: str) -> None:
        """Initialize an external service error."""
        super().__init__(
            502,
            "EXTERNAL_SERVICE_ERROR",
            f"Error from {service}: {message}",
            {"service": service},
        )
