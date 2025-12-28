from api.services.storage import service as storage_service


def test_get_storage_backend_uses_r2_access_key(monkeypatch):
    class DummyR2:
        def __init__(self, *, endpoint, bucket, access_key_id, secret_access_key):
            self.endpoint = endpoint
            self.bucket = bucket
            self.access_key_id = access_key_id
            self.secret_access_key = secret_access_key

    monkeypatch.setattr(storage_service, "R2Storage", DummyR2)
    monkeypatch.setattr(storage_service.settings, "storage_backend", "r2")
    monkeypatch.setattr(storage_service.settings, "r2_endpoint", "https://example")
    monkeypatch.setattr(storage_service.settings, "r2_bucket", "bucket")
    monkeypatch.setattr(storage_service.settings, "r2_access_key_id", None)
    monkeypatch.setattr(storage_service.settings, "r2_access_key", "fallback-key")
    monkeypatch.setattr(storage_service.settings, "r2_secret_access_key", "secret")

    backend = storage_service.get_storage_backend()
    assert backend.access_key_id == "fallback-key"
    assert backend.endpoint == "https://example"
    assert backend.bucket == "bucket"
