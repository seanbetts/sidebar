"""Favicon download and storage helpers."""

from __future__ import annotations

import hashlib
import io
import logging
from contextlib import suppress
from datetime import UTC, datetime
from urllib.parse import urlparse

import requests
from PIL import Image  # type: ignore[import-untyped]

from api.services.storage.service import get_storage_backend
from api.services.web_save_constants import USER_AGENT

logger = logging.getLogger(__name__)

FAVICON_BUCKET_PREFIX = "favicons/"
MAX_FAVICON_BYTES = 1_000_000
MAX_FAVICON_DIMENSION = 256


class FaviconService:
    """Service for downloading and storing favicons."""

    @staticmethod
    def build_storage_key(user_id: str, domain: str) -> str:
        """Build a deterministic storage key for a favicon."""
        normalized = domain.strip().lower()
        digest = hashlib.sha256(normalized.encode("utf-8")).hexdigest()
        return f"{FAVICON_BUCKET_PREFIX}{user_id}/{digest}.png"

    @staticmethod
    def fetch_and_store_favicon(
        user_id: str,
        domain: str,
        favicon_url: str,
        *,
        timeout: int = 10,
    ) -> str | None:
        """Download a favicon, normalize it, and store in the configured backend."""
        parsed = urlparse(favicon_url)
        if parsed.scheme not in {"http", "https"}:
            return None

        try:
            raw_bytes, content_type = FaviconService._download_favicon(
                favicon_url, timeout=timeout
            )
            if raw_bytes is None:
                return None
            normalized = FaviconService._normalize_favicon(raw_bytes, content_type)
            if normalized is None:
                return None
            storage_key = FaviconService.build_storage_key(user_id, domain)
            storage = get_storage_backend()
            storage.put_object(storage_key, normalized, content_type="image/png")
            return storage_key
        except Exception as exc:
            logger.warning(
                "favicon fetch/store failed url=%s error=%s", favicon_url, exc
            )
            return None

    @staticmethod
    def metadata_payload(
        *,
        favicon_url: str | None,
        favicon_r2_key: str | None = None,
    ) -> dict[str, object]:
        """Build metadata fields for favicon updates."""
        payload: dict[str, object] = {}
        if favicon_url:
            payload["favicon_url"] = favicon_url
            payload["favicon_extracted_at"] = datetime.now(UTC).isoformat()
        if favicon_r2_key:
            payload["favicon_r2_key"] = favicon_r2_key
        return payload

    @staticmethod
    def _download_favicon(
        favicon_url: str,
        *,
        timeout: int,
    ) -> tuple[bytes | None, str | None]:
        headers = {"User-Agent": USER_AGENT}
        response = requests.get(
            favicon_url,
            headers=headers,
            timeout=timeout,
            allow_redirects=True,
            stream=True,
        )
        response.raise_for_status()
        content_type = response.headers.get("Content-Type")
        total = 0
        chunks: list[bytes] = []
        for chunk in response.iter_content(chunk_size=8192):
            if not chunk:
                continue
            total += len(chunk)
            if total > MAX_FAVICON_BYTES:
                response.close()
                return None, content_type
            chunks.append(chunk)
        response.close()
        return b"".join(chunks), content_type

    @staticmethod
    def _normalize_favicon(
        raw_bytes: bytes,
        content_type: str | None,
    ) -> bytes | None:
        if not raw_bytes:
            return None
        content_type = (content_type or "").split(";", 1)[0].strip().lower()
        if content_type == "image/svg+xml":
            return None
        if raw_bytes.lstrip().startswith(b"<svg") or raw_bytes.lstrip().startswith(
            b"<?xml"
        ):
            return None

        try:
            image = Image.open(io.BytesIO(raw_bytes))
            image.load()
        except Exception:
            return None

        if getattr(image, "is_animated", False):
            with suppress(Exception):
                image.seek(0)

        if image.mode not in {"RGB", "RGBA"}:
            image = image.convert("RGBA")

        image.thumbnail((MAX_FAVICON_DIMENSION, MAX_FAVICON_DIMENSION), Image.LANCZOS)

        output = io.BytesIO()
        image.save(output, format="PNG", optimize=True)
        return output.getvalue()
