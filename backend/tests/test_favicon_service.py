"""Tests for favicon service."""

from __future__ import annotations

import io

from PIL import Image

from api.services import favicon_service


class _FakeResponse:
    def __init__(self, data: bytes, content_type: str = "image/png") -> None:
        self._data = data
        self.headers = {"Content-Type": content_type}
        self.status_code = 200

    def raise_for_status(self) -> None:
        return None

    def iter_content(self, chunk_size: int = 8192):
        for idx in range(0, len(self._data), chunk_size):
            yield self._data[idx : idx + chunk_size]

    def close(self) -> None:
        return None


class _FakeStorage:
    def __init__(self) -> None:
        self.calls: list[tuple[str, bytes, str | None]] = []
        self.exists_calls: list[str] = []

    def object_exists(self, key: str) -> bool:
        self.exists_calls.append(key)
        return False

    def put_object(self, key: str, data: bytes, content_type: str | None = None):
        self.calls.append((key, data, content_type))


def _make_png_bytes(size: int = 64) -> bytes:
    image = Image.new("RGBA", (size, size), (255, 0, 0, 255))
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def test_fetch_and_store_favicon(monkeypatch):
    png_bytes = _make_png_bytes(size=512)
    fake_response = _FakeResponse(png_bytes)
    storage = _FakeStorage()

    monkeypatch.setattr(
        favicon_service.requests,
        "get",
        lambda *args, **kwargs: fake_response,
    )
    monkeypatch.setattr(
        favicon_service,
        "get_storage_backend",
        lambda: storage,
    )

    key = favicon_service.FaviconService.fetch_and_store_favicon(
        "sub.example.com", "https://example.com/favicon.png"
    )

    assert key == favicon_service.FaviconService.build_storage_key("example.com")
    assert storage.calls
    stored_key, data, content_type = storage.calls[0]
    assert stored_key == key
    assert content_type == "image/png"
    assert data.startswith(b"\x89PNG")
