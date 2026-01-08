from pathlib import Path

from api.metrics import storage_operations_total
from api.services.storage.local import LocalStorage


def _counter_value(counter, operation: str, status: str) -> float:
    return counter.labels(operation, status)._value.get()


def test_storage_metrics_increment(tmp_path: Path):
    storage = LocalStorage(tmp_path)
    key = "notes/test.txt"
    data = b"hello"

    start_put = _counter_value(storage_operations_total, "put", "success")
    start_get = _counter_value(storage_operations_total, "get", "success")
    start_delete = _counter_value(storage_operations_total, "delete", "success")
    start_exists = _counter_value(storage_operations_total, "exists", "success")

    storage.put_object(key, data, content_type="text/plain")
    storage.get_object(key)
    storage.object_exists(key)
    storage.delete_object(key)

    end_put = _counter_value(storage_operations_total, "put", "success")
    end_get = _counter_value(storage_operations_total, "get", "success")
    end_delete = _counter_value(storage_operations_total, "delete", "success")
    end_exists = _counter_value(storage_operations_total, "exists", "success")

    assert end_put == start_put + 1
    assert end_get == start_get + 1
    assert end_exists == start_exists + 1
    assert end_delete == start_delete + 1
