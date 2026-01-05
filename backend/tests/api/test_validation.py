import uuid

import pytest

from api.exceptions import BadRequestError
from api.utils.validation import parse_optional_uuid, parse_uuid


def test_parse_uuid_success():
    value = str(uuid.uuid4())
    parsed = parse_uuid(value, "note", "id")
    assert str(parsed) == value


def test_parse_uuid_failure():
    with pytest.raises(BadRequestError) as exc:
        parse_uuid("not-a-uuid", "note", "id")

    assert "Invalid note ID" in str(exc.value)


def test_parse_optional_uuid_none():
    assert parse_optional_uuid(None, "note", "id") is None
