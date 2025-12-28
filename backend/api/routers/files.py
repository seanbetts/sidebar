"""Files router for browsing workspace files."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.files_workspace_service import FilesWorkspaceService

router = APIRouter(prefix="/files", tags=["files"])

@router.get("/tree")
async def get_file_tree(
    basePath: str = "documents",
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Get the file tree for a subdirectory within workspace.

    Args:
        base_path: Subdirectory within workspace (e.g., "documents")

    Returns:
        {
            "children": [...]  # Direct children of the base_path folder
        }
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
    if not query:
        raise HTTPException(status_code=400, detail="query required")
    return FilesWorkspaceService.search(db, user_id, query, basePath, limit=limit)


@router.post("/folder")
async def create_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Create a folder within workspace.

    Body:
        {
            "basePath": "documents",
            "path": "Folder/Subfolder"
        }
    """
    base_path = request.get("basePath", "documents")
    path = (request.get("path") or "").strip("/")

    if not path:
        raise HTTPException(status_code=400, detail="path required")

    return FilesWorkspaceService.create_folder(db, user_id, base_path, path)


@router.post("/rename")
async def rename_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Rename a file or folder within workspace.

    Body:
        {
            "basePath": "documents",
            "oldPath": "relative/path/to/item",
            "newName": "new-name.txt"
        }
    """
    base_path = request.get("basePath", "documents")
    old_path = request.get("oldPath", "")
    new_name = request.get("newName", "")

    if not old_path or not new_name:
        raise HTTPException(status_code=400, detail="oldPath and newName required")

    return FilesWorkspaceService.rename(db, user_id, base_path, old_path, new_name)


@router.post("/move")
async def move_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Move a file or folder within workspace.

    Body:
        {
            "basePath": "documents",
            "path": "relative/path/to/item",
            "destination": "relative/path/to/folder"
        }
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")
    destination = request.get("destination", "")

    if not path:
        raise HTTPException(status_code=400, detail="path required")

    return FilesWorkspaceService.move(db, user_id, base_path, path, destination)


@router.post("/delete")
async def delete_file_or_folder(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Delete a file or folder within workspace.

    Body:
        {
            "basePath": "documents",
            "path": "relative/path/to/item"
        }
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")

    if not path or path == "/":
        raise HTTPException(status_code=400, detail="Cannot delete root directory")

    return FilesWorkspaceService.delete(db, user_id, base_path, path)


@router.get("/download")
async def download_file(
    basePath: str = "documents",
    path: str = "",
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    if not path:
        raise HTTPException(status_code=400, detail="path parameter required")
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
    """
    Get the content of a file.

    Query params:
        basePath: Subdirectory within workspace (e.g., "documents")
        path: Relative path to file within basePath

    Returns:
        {
            "content": "file content...",
            "name": "filename.md",
            "path": "relative/path.md",
            "modified": 1234567890
        }
    """
    if not path:
        raise HTTPException(status_code=400, detail="path parameter required")

    return FilesWorkspaceService.get_content(db, user_id, basePath, path)


@router.post("/content")
async def update_file_content(
    request: dict,
    user_id: str = Depends(get_current_user_id),
    _: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db),
):
    """
    Update the content of a file.

    Body:
        {
            "basePath": "documents",
            "path": "relative/path/file.md",
            "content": "new content..."
        }

    Returns:
        {
            "success": true,
            "modified": 1234567890
        }
    """
    base_path = request.get("basePath", "documents")
    path = request.get("path", "")
    content = request.get("content", "")

    if not path:
        raise HTTPException(status_code=400, detail="path required")

    return FilesWorkspaceService.update_content(db, user_id, base_path, path, content)
