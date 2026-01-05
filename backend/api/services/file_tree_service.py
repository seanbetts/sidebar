"""Helpers for file tree building and path normalization."""
from __future__ import annotations

from typing import Any, Dict


class FileTreeService:
    """Build tree responses and normalize file paths."""

    @staticmethod
    def normalize_base_path(base_path: str) -> str:
        """Normalize a base path by stripping slashes."""
        return (base_path or "").strip("/")

    @staticmethod
    def full_path(base_path: str, relative_path: str) -> str:
        """Build a full path from base and relative paths.

        Args:
            base_path: Base folder path.
            relative_path: Relative file or folder path.

        Returns:
            Full path string.
        """
        base = FileTreeService.normalize_base_path(base_path)
        relative = (relative_path or "").strip("/")
        if not base:
            return relative
        return f"{base}/{relative}" if relative else base

    @staticmethod
    def relative_path(base_path: str, full_path: str) -> str:
        """Return a relative path from a full path and base.

        Args:
            base_path: Base folder path.
            full_path: Full path including base.

        Returns:
            Relative path string.
        """
        base = FileTreeService.normalize_base_path(base_path)
        path = (full_path or "").strip("/")
        if not base:
            return path
        if path == base:
            return ""
        if path.startswith(f"{base}/"):
            return path[len(base) + 1 :]
        return ""

    @staticmethod
    def bucket_key(user_id: str, full_path: str) -> str:
        """Build a storage bucket key for a user and path.

        Args:
            user_id: Current user ID.
            full_path: Full path to store.

        Returns:
            Bucket key string.
        """
        return f"{user_id}/{full_path.strip('/')}"

    @staticmethod
    def build_tree(records: list, base_path: str) -> Dict[str, Any]:
        """Build a directory tree from file records.

        Args:
            records: File records to include.
            base_path: Base folder path.

        Returns:
            Tree dict suitable for UI rendering.
        """
        root: Dict[str, Any] = {
            "name": base_path or "files",
            "path": "/",
            "type": "directory",
            "children": [],
            "expanded": False,
        }
        index: Dict[str, Dict[str, Any]] = {"": root}

        for record in records:
            if record.deleted_at is not None:
                continue
            rel_path = FileTreeService.relative_path(base_path, record.path)
            if rel_path == "" and record.category != "folder":
                continue

            parts = [part for part in rel_path.split("/") if part]
            if record.category == "folder" and not parts:
                continue

            current = ""
            parent_node = root
            for part in parts[:-1]:
                current = f"{current}/{part}" if current else part
                if current not in index:
                    node: Dict[str, Any] = {
                        "name": part,
                        "path": current,
                        "type": "directory",
                        "children": [],
                        "expanded": False,
                    }
                    index[current] = node
                    parent_node["children"].append(node)
                parent_node = index[current]

            if record.category == "folder":
                folder_path = "/".join(parts)
                if folder_path and folder_path not in index:
                    folder_node: Dict[str, Any] = {
                        "name": parts[-1],
                        "path": folder_path,
                        "type": "directory",
                        "children": [],
                        "expanded": False,
                    }
                    index[folder_path] = folder_node
                    parent_node["children"].append(folder_node)
                continue

            if not parts:
                continue

            filename = parts[-1]
            parent_node["children"].append(
                {
                    "name": filename,
                    "path": "/".join(parts),
                    "type": "file",
                    "size": record.size,
                    "modified": record.updated_at.timestamp() if record.updated_at else None,
                }
            )

        def sort_children(node: Dict[str, Any]) -> None:
            """Sort children nodes with directories first, then by name."""
            node["children"].sort(
                key=lambda item: (item.get("type") != "directory", item.get("name", "").lower())
            )
            for child in node["children"]:
                if child.get("type") == "directory":
                    sort_children(child)

        sort_children(root)
        return root
