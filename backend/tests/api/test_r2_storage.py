from datetime import datetime, timezone

import pytest
from botocore.exceptions import ClientError

from api.services.storage.r2 import R2Storage


class FakeS3Client:
    def __init__(self):
        self.calls = []
        self.list_responses = []

    def list_objects_v2(self, **params):
        self.calls.append(("list", params))
        return self.list_responses.pop(0)

    def get_object(self, **params):
        self.calls.append(("get", params))
        return {"Body": FakeBody(b"hello")}

    def put_object(self, **params):
        self.calls.append(("put", params))
        return {"ETag": '"etag"'}

    def delete_object(self, **params):
        self.calls.append(("delete", params))
        return {}

    def copy_object(self, **params):
        self.calls.append(("copy", params))
        return {}

    def head_object(self, **params):
        self.calls.append(("head", params))
        return {}


class FakeBody:
    def __init__(self, data):
        self._data = data

    def read(self):
        return self._data


@pytest.fixture
def fake_client(monkeypatch):
    client = FakeS3Client()
    monkeypatch.setattr("api.services.storage.r2.boto3.client", lambda *_, **__: client)
    return client


def test_list_objects_strips_leading_slash(fake_client):
    fake_client.list_responses = [
        {
            "Contents": [
                {
                    "Key": "docs/file.txt",
                    "Size": 12,
                    "ETag": '"abc"',
                    "LastModified": datetime(2024, 1, 1, tzinfo=timezone.utc),
                }
            ],
            "IsTruncated": False,
        }
    ]
    storage = R2Storage(
        endpoint="https://example",
        bucket="bucket",
        access_key_id="key",
        secret_access_key="secret",
    )
    results = list(storage.list_objects("/docs"))
    assert results[0].key == "docs/file.txt"
    assert fake_client.calls[0][1]["Prefix"] == "docs"


def test_list_objects_handles_pagination(fake_client):
    fake_client.list_responses = [
        {
            "Contents": [{"Key": "a.txt", "Size": 1}],
            "IsTruncated": True,
            "NextContinuationToken": "next",
        },
        {
            "Contents": [{"Key": "b.txt", "Size": 2}],
            "IsTruncated": False,
        },
    ]
    storage = R2Storage(
        endpoint="https://example",
        bucket="bucket",
        access_key_id="key",
        secret_access_key="secret",
    )
    results = list(storage.list_objects("docs", recursive=False))
    assert [item.key for item in results] == ["a.txt", "b.txt"]
    assert fake_client.calls[0][1]["Delimiter"] == "/"


def test_put_get_delete_copy_object(fake_client):
    storage = R2Storage(
        endpoint="https://example",
        bucket="bucket",
        access_key_id="key",
        secret_access_key="secret",
    )
    storage.put_object("/docs/file.txt", b"data", content_type="text/plain")
    storage.get_object("/docs/file.txt")
    storage.copy_object("/docs/file.txt", "/docs/other.txt")
    storage.delete_object("/docs/file.txt")

    operations = [call[0] for call in fake_client.calls]
    assert operations == ["put", "get", "copy", "delete"]
    assert fake_client.calls[0][1]["Key"] == "docs/file.txt"


def test_object_exists_handles_missing(fake_client):
    storage = R2Storage(
        endpoint="https://example",
        bucket="bucket",
        access_key_id="key",
        secret_access_key="secret",
    )

    def head_object(**_):
        error = {"Error": {"Code": "404"}, "ResponseMetadata": {"HTTPStatusCode": 404}}
        raise ClientError(error, "HeadObject")

    fake_client.head_object = head_object
    assert storage.object_exists("missing.txt") is False
