from api.services.storage.local import LocalStorage


def test_local_storage_crud(tmp_path):
    storage = LocalStorage(tmp_path)
    storage.put_object("docs/file.txt", b"hello", content_type="text/plain")

    assert storage.object_exists("docs/file.txt") is True
    assert storage.get_object("docs/file.txt") == b"hello"

    storage.copy_object("docs/file.txt", "docs/copy.txt")
    assert storage.get_object("docs/copy.txt") == b"hello"

    storage.delete_object("docs/file.txt")
    assert storage.object_exists("docs/file.txt") is False


def test_local_storage_list_objects(tmp_path):
    storage = LocalStorage(tmp_path)
    storage.put_object("docs/a.txt", b"a")
    storage.put_object("docs/nested/b.txt", b"b")

    recursive = list(storage.list_objects("docs", recursive=True))
    non_recursive = list(storage.list_objects("docs", recursive=False))

    recursive_keys = {obj.key for obj in recursive}
    non_recursive_keys = {obj.key for obj in non_recursive}

    assert recursive_keys == {"docs/a.txt", "docs/nested/b.txt"}
    assert non_recursive_keys == {"docs/a.txt"}
