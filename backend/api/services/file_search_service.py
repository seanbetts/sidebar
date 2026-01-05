"""Search service for ingested file metadata and content."""
from __future__ import annotations

from pathlib import Path
import logging
from typing import Pattern

from api.models.file_ingestion import IngestedFile, FileDerivative
from api.services.skill_file_ops_paths import (
    ensure_allowed_path,
    is_profile_images_path,
    normalize_path,
    session_for_user,
)
from api.services.storage.service import get_storage_backend

logger = logging.getLogger(__name__)


class FileSearchService:
    """Service layer for searching ingested files."""

    @staticmethod
    def search_entries(
        user_id: str,
        directory: str,
        *,
        name_pattern: Pattern[str] | None,
        content_pattern: Pattern[str] | None,
        max_results: int,
    ) -> list[dict]:
        """Search ingested files by name and/or content.

        Args:
            user_id: Current user ID.
            directory: Base directory for the search.
            name_pattern: Compiled regex for file names.
            content_pattern: Compiled regex for file contents.
            max_results: Max results to return.

        Returns:
            List of search result dictionaries.
        """
        base_path = normalize_path(directory)
        if base_path:
            ensure_allowed_path(base_path)

        with session_for_user(user_id) as db:
            query = (
                db.query(IngestedFile)
                .filter(
                    IngestedFile.user_id == user_id,
                    IngestedFile.deleted_at.is_(None),
                    IngestedFile.path.is_not(None),
                )
            )
            if base_path:
                query = query.filter(IngestedFile.path.like(f"{base_path}/%"))
            records = query.order_by(IngestedFile.created_at.desc()).all()
            file_ids = [record.id for record in records]
            derivatives_by_file = {}
            if file_ids:
                derivatives_by_file = {
                    item.file_id: item
                    for item in db.query(FileDerivative)
                    .filter(
                        FileDerivative.file_id.in_(file_ids),
                        FileDerivative.kind == "ai_md",
                    )
                    .all()
                }

        storage = get_storage_backend() if content_pattern is not None else None
        results: list[dict] = []

        for record in records:
            if not record.path or is_profile_images_path(record.path):
                continue
            rel_path = (
                record.path[len(base_path) + 1 :]
                if base_path and record.path.startswith(f"{base_path}/")
                else record.path
            )
            if not rel_path:
                continue
            name = Path(rel_path).name

            if name_pattern and not name_pattern.match(name):
                continue

            if content_pattern is None:
                results.append(
                    {
                        "path": record.path,
                        "name": name,
                        "size": record.size_bytes,
                        "match_type": "name",
                    }
                )
                if len(results) >= max_results:
                    break
                continue

            derivative = derivatives_by_file.get(record.id)
            if not derivative:
                continue
            try:
                assert storage is not None
                content = storage.get_object(derivative.storage_key).decode("utf-8", errors="ignore")
            except Exception as exc:
                logger.warning(
                    "Failed to load file content during search",
                    exc_info=exc,
                    extra={
                        "user_id": user_id,
                        "file_id": str(record.id),
                        "storage_key": derivative.storage_key,
                        "path": record.path,
                    },
                )
                continue

            matches = list(content_pattern.finditer(content))
            if not matches:
                continue

            lines = content.split("\n")
            match_lines = []
            for match in matches[:5]:
                line_num = content[:match.start()].count("\n") + 1
                if line_num <= len(lines):
                    line_content = lines[line_num - 1].strip()
                    match_lines.append(
                        {
                            "line": line_num,
                            "content": line_content[:100],
                        }
                    )

            results.append(
                {
                    "path": record.path,
                    "name": name,
                    "size": record.size_bytes,
                    "match_type": "content",
                    "match_count": len(matches),
                    "matches": match_lines,
                }
            )

            if len(results) >= max_results:
                break

        return results
