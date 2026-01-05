"""Common validation utilities."""
from __future__ import annotations

from typing import Optional
import uuid

from api.exceptions import BadRequestError


def parse_uuid(
    value: str,
    resource_name: str = "resource",
    field_name: str = "id",
) -> uuid.UUID:
    """Parse a UUID string with consistent error handling.

    Args:
        value: String to parse as UUID.
        resource_name: Resource name for error messaging.
        field_name: Field name for error messaging.

    Returns:
        Parsed UUID object.

    Raises:
        BadRequestError: If value is not a valid UUID.
    """
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError, AttributeError) as exc:
        field_label = "ID" if field_name.lower() == "id" else field_name
        raise BadRequestError(
            f"Invalid {resource_name} {field_label}: must be a valid UUID"
        ) from exc


def parse_optional_uuid(
    value: Optional[str],
    resource_name: str = "resource",
    field_name: str = "id",
) -> Optional[uuid.UUID]:
    """Parse an optional UUID string.

    Args:
        value: String to parse as UUID, or None.
        resource_name: Resource name for error messaging.
        field_name: Field name for error messaging.

    Returns:
        Parsed UUID object or None.
    """
    if value is None:
        return None
    return parse_uuid(value, resource_name, field_name)
