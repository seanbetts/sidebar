from types import SimpleNamespace

import pytest

from api.services.memory_tools import formatters, operations, path_utils
from api.models.user_memory import UserMemory


def test_normalize_path_accepts_memories_root():
    assert path_utils.normalize_path("/memories") == "/memories"


def test_normalize_path_rejects_traversal():
    with pytest.raises(ValueError):
        path_utils.normalize_path("/memories/../secret")


def test_is_visible_path_filters_hidden_and_node_modules():
    assert path_utils.is_visible_path("/memories/visible.md") is True
    assert path_utils.is_visible_path("/memories/.hidden.md") is False
    assert path_utils.is_visible_path("/memories/node_modules/foo.md") is False


def test_format_file_view_with_range():
    content = "one\ntwo\nthree"
    result = formatters.format_file_view("/memories/test.md", content, [2, 3])
    assert "     2\ttwo" in result
    assert "     3\tthree" in result


def test_format_file_view_rejects_bad_range():
    with pytest.raises(ValueError):
        formatters.format_file_view("/memories/test.md", "one", ["a", "b"])


def test_format_directory_listing_excludes_hidden():
    memories = [
        SimpleNamespace(path="/memories/alpha.md", content="hello"),
        SimpleNamespace(path="/memories/.hidden.md", content="secret"),
    ]
    listing = formatters.format_directory_listing("/memories", memories)
    assert "/memories/alpha.md" in listing
    assert "/memories/.hidden.md" not in listing


def test_memory_create_and_view(test_db):
    result = operations.handle_create(
        test_db,
        "user-1",
        {"path": "/memories/test.md", "file_text": "hello"},
    )
    assert result["success"] is True

    view = operations.handle_view(test_db, "user-1", {"path": "/memories/test.md"})
    assert view["success"] is True
    assert "hello" in view["data"]["content"]


def test_memory_str_replace_duplicate(test_db):
    memory = UserMemory(user_id="user-1", path="/memories/a.md", content="hi\nhi")
    test_db.add(memory)
    test_db.commit()

    result = operations.handle_str_replace(
        test_db,
        "user-1",
        {"path": "/memories/a.md", "old_str": "hi", "new_str": "yo"},
    )
    assert result["success"] is False
    assert "Multiple occurrences" in result["error"]


def test_memory_insert_invalid_line(test_db):
    memory = UserMemory(user_id="user-1", path="/memories/b.md", content="one")
    test_db.add(memory)
    test_db.commit()

    result = operations.handle_insert(
        test_db,
        "user-1",
        {"path": "/memories/b.md", "insert_line": 5, "insert_text": "two"},
    )
    assert result["success"] is False
    assert "Invalid `insert_line`" in result["error"]


def test_memory_rename_and_delete(test_db):
    memory = UserMemory(user_id="user-1", path="/memories/old.md", content="hello")
    test_db.add(memory)
    test_db.commit()

    rename = operations.handle_rename(
        test_db,
        "user-1",
        {"old_path": "/memories/old.md", "new_path": "/memories/new.md"},
    )
    assert rename["success"] is True

    updated = (
        test_db.query(UserMemory)
        .filter(UserMemory.user_id == "user-1", UserMemory.path == "/memories/new.md")
        .first()
    )
    assert updated is not None

    delete = operations.handle_delete(
        test_db,
        "user-1",
        {"path": "/memories/new.md"},
    )
    assert delete["success"] is True
    assert test_db.query(UserMemory).filter(UserMemory.user_id == "user-1").count() == 0
