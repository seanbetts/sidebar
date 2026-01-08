from datetime import UTC, datetime
from types import SimpleNamespace

from api.services.file_tree_service import FileTreeService


def _record(path, category="file", size=0, deleted_at=None):
    return SimpleNamespace(
        path=path,
        category=category,
        size=size,
        updated_at=datetime(2024, 1, 1, tzinfo=UTC),
        deleted_at=deleted_at,
    )


def test_path_helpers():
    assert FileTreeService.normalize_base_path("/docs/") == "docs"
    assert FileTreeService.full_path("docs", "file.txt") == "docs/file.txt"
    assert FileTreeService.full_path("", "file.txt") == "file.txt"
    assert FileTreeService.relative_path("docs", "docs/file.txt") == "file.txt"
    assert FileTreeService.relative_path("docs", "other/file.txt") == ""


def test_bucket_key():
    assert (
        FileTreeService.bucket_key("user-1", "/docs/file.txt") == "user-1/docs/file.txt"
    )


def test_build_tree_sorts_and_filters():
    records = [
        _record("docs/a.txt", size=1),
        _record("docs/folder", category="folder"),
        _record("docs/folder/b.txt", size=2),
        _record("docs/removed.txt", deleted_at=datetime(2024, 1, 2, tzinfo=UTC)),
    ]
    tree = FileTreeService.build_tree(records, "docs")
    children = tree["children"]
    assert children[0]["type"] == "directory"
    assert children[0]["name"] == "folder"
    assert children[1]["name"] == "a.txt"
    assert children[0]["children"][0]["name"] == "b.txt"
