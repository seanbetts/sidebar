"""Files router for browsing workspace files."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.exceptions import BadRequestError
from api.services.files_workspace_service import FilesWorkspaceService

router = APIRouter(prefix="/files", tags=["files"])

@router.get("/tree")
async def get_file_tree(
    basePath: str = "documents",
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return the file tree for a workspace subdirectory.

    Args:
        basePath: Subdirectory within workspace (e.g., "documents").
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Tree payload containing children of the basePath folder.
    """
    return FilesWorkspaceService.get_tree(db, user_id, basePath)


@router.post("/search")
async def search_files(
    query: str,
    basePath: str = "documents",
    limit: int = 50,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Search files by name or content.

    Args:
        query: Search query string.
        basePath: Subdirectory within workspace (e.g., "documents").
        limit: Max results to return. Defaults to 50.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Search results payload.

    Raises:
        BadRequestError: If query is missing.
    """
    if not query:
        raise BadRequestError("query required")
    return FilesWorkspaceService.search(db, user_id, query, base_path=basePath, limit=limit)


@router.post("/folder")
async def create_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Create a folder within workspace.

    Args:
        request: Request payload with basePath and path.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Folder creation result.

    Raises:
        BadRequestError: If path is missing.
    """
    base_path = request.get("basePath", "documents")
    path = (request.get("path") or "").strip("/")

    if not path:
        raise BadRequestError("path required")

    return FilesWorkspaceService.create_folder(db, user_id, base_path, path)


@router.post("/rename")
async def rename_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Rename a file or folder within workspace.

    Args:
        request: Request payload with basePath, oldPath, newName.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Rename result.

    Raises:
        BadRequestError: If required fields are missing.
    """
    base_path = request.get("basePath", "documents")
    old_path = request.get("oldPath", "")
    new_name = request.get("newName", "")

    if not old_path or not new_name:
        raise BadRequestError("oldPath and newName required")

    return FilesWorkspaceService.rename(db, user_id, base_path, old_path, new_name)


@router.post("/move")
async def move_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Move a file or folder within workspace.

    Args:
        request: Request payload with basePath, path, destination.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Move result.

    Raises:
        BadRequestError: If path is missing.
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")
    destination = request.get("destination", "")

    if not path:
        raise BadRequestError("path required")

    return FilesWorkspaceService.move(db, user_id, base_path, path, destination)


@router.post("/delete")
async def delete_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Delete a file or folder within workspace.

    Args:
        request: Request payload with basePath and path.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Delete result.

    Raises:
        BadRequestError: If path is missing or points to root.
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")

    if not path or path == "/":
        raise BadRequestError("Cannot delete root directory")

    return FilesWorkspaceService.delete(db, user_id, base_path, path)


@router.get("/download")
async def download_file(
    basePath: str = "documents",
    path: str = "",
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Download a file from workspace.

    Args:
        basePath: Subdirectory within workspace (e.g., "documents").
        path: Relative path to file within basePath.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        File content response with attachment headers.

    Raises:
        BadRequestError: If path is missing.
    """
    if not path:
        raise BadRequestError("path parameter required")
    result = FilesWorkspaceService.download(db, user_id, basePath, path)
    return Response(
        result["content"],
        media_type=result["content_type"],
        headers={"Content-Disposition": f'attachment; filename="{result["filename"]}"'},
    )


@router.get("/content")
async def get_file_content(
    basePath: str = "documents",
    path: str = "",
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Return the content of a file.

    Args:
        basePath: Subdirectory within workspace (e.g., "documents").
        path: Relative path to file within basePath.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        File content payload with metadata.

    Raises:
        BadRequestError: If path is missing.
    """
    if not path:
        raise BadRequestError("path parameter required")

    return FilesWorkspaceService.get_content(db, user_id, basePath, path)


@router.post("/content")
async def update_file_content(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """Update the content of a file.

    Args:
        request: Request payload with basePath, path, content.
        user_id: Current authenticated user ID.
        _: Authorization token (validated).
        db: Database session.

    Returns:
        Update result payload with modified time.

    Raises:
        BadRequestError: If path is missing.
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")
    content = request.get("content", "")

    if not path:
        raise BadRequestError("path required")

    return FilesWorkspaceService.update_content(db, user_id, base_path, path, content)
