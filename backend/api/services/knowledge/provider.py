"""Singleton provider for the docs indexer."""

from __future__ import annotations

import logging
from pathlib import Path

from api.services.knowledge.docs_indexer import DocsIndexer

logger = logging.getLogger(__name__)

_indexer: DocsIndexer | None = None


def init_docs_indexer(docs_root: Path | None = None) -> DocsIndexer:
    """Initialise the global docs indexer.

    Args:
        docs_root: Path to the product docs directory. Defaults to
            ``docs/product`` relative to the repo root.
    """
    global _indexer  # noqa: PLW0603
    if docs_root is None:
        docs_root = Path(__file__).resolve().parents[4] / "docs" / "product"
    indexer = DocsIndexer(docs_root)
    indexer.build()
    _indexer = indexer
    return indexer


def get_docs_indexer() -> DocsIndexer:
    """Return the global docs indexer. Raises if not initialised."""
    if _indexer is None:
        raise RuntimeError(
            "Docs indexer not initialised. Call init_docs_indexer() at startup."
        )
    return _indexer
