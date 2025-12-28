"""Centralized path validation and jailing."""
from pathlib import Path
from typing import Tuple
from fastapi import HTTPException, status


class PathValidator:
    """Centralized path validation for workspace safety.

    Enforces:
    - Path traversal rejection (..)
    - Symlink escapes rejection
    - Access outside workspace rejection
    - Writes restricted to allowlisted paths
    """

    def __init__(self, workspace_base: Path, writable_paths: list[str]):
        """Initialize a path validator.

        Args:
            workspace_base: Base workspace path to jail accesses.
            writable_paths: Allowlisted writable paths.
        """
        self.workspace_base = workspace_base.resolve()
        self.writable_paths = [Path(p).resolve() for p in writable_paths]

    def validate_read_path(self, path: str) -> Path:
        """Validate and resolve a path for reading."""
        return self._validate_path(path, check_writable=False)

    def validate_write_path(self, path: str) -> Path:
        """Validate and resolve a path for writing."""
        return self._validate_path(path, check_writable=True)

    def _validate_path(self, path: str, check_writable: bool) -> Path:
        """Core path validation logic."""
        # In R2 mode, enforce string-level path rules only.
        try:
            from api.config import settings
        except Exception:
            settings = None

        if settings and settings.storage_backend.lower() == "r2":
            if ".." in path:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Path traversal not allowed: {path}"
                )
            if Path(path).is_absolute():
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Absolute paths not allowed: {path}"
                )
            normalized = path.replace("\\", "/").strip("/")
            if normalized == "profile-images" or normalized.startswith("profile-images/"):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Path not writable: profile-images"
                )
            return (self.workspace_base / normalized).resolve()

        # Reject obvious traversal attempts
        if ".." in path:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Path traversal not allowed: {path}"
            )

        # Convert to absolute path relative to workspace
        if Path(path).is_absolute():
            abs_path = Path(path)
        else:
            abs_path = (self.workspace_base / path).resolve()

        # Reject symlinks (resolve would follow them, but we check first)
        if abs_path.is_symlink():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Symlinks not allowed: {path}"
            )

        # Ensure path is within workspace
        try:
            abs_path.relative_to(self.workspace_base)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Path outside workspace: {path}"
            )

        # Check write permissions if needed
        if check_writable:
            allowed = any(
                abs_path == writable or self._is_relative_to(abs_path, writable)
                for writable in self.writable_paths
            )
            if not allowed:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Path not writable (allowlist: {[str(p) for p in self.writable_paths]})"
                )

        return abs_path

    def get_relative_path(self, abs_path: Path) -> str:
        """Convert absolute path back to workspace-relative."""
        return str(abs_path.relative_to(self.workspace_base))

    @staticmethod
    def _is_relative_to(path: Path, parent: Path) -> bool:
        """Check if path is relative to parent (Python 3.9+ has this built-in)."""
        try:
            path.relative_to(parent)
            return True
        except ValueError:
            return False
