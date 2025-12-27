"""Files router for browsing workspace files."""
from __future__ import annotations

import mimetypes
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from sqlalchemy.orm import Session

from api.auth import verify_bearer_token
from api.db.dependencies import get_current_user_id
from api.db.session import get_db
from api.services.files_service import FilesService
from api.services.storage.service import get_storage_backend

router = APIRouter(prefix="/files", tags=["files"])

storage_backend = get_storage_backend()


def _normalize_base_path(base_path: str) -> str:
    return (base_path or "").strip("/")


def _full_path(base_path: str, relative_path: str) -> str:
    base = _normalize_base_path(base_path)
    relative = (relative_path or "").strip("/")
    if not base:
        return relative
    return f"{base}/{relative}" if relative else base


def _relative_path(base_path: str, full_path: str) -> str:
    base = _normalize_base_path(base_path)
    path = (full_path or "").strip("/")
    if not base:
        return path
    if path == base:
        return ""
    if path.startswith(f"{base}/"):
        return path[len(base) + 1 :]
    return ""


def _bucket_key(user_id: str, full_path: str) -> str:
    return f"{user_id}/{full_path.strip('/')}"


def _build_tree_from_records(records: list, base_path: str) -> Dict[str, Any]:
    root = {
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
        rel_path = _relative_path(base_path, record.path)
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
                node = {
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
                node = {
                    "name": parts[-1],
                    "path": folder_path,
                    "type": "directory",
                    "children": [],
                    "expanded": False,
                }
                index[folder_path] = node
                parent_node["children"].append(node)
            continue

        if not parts:
            continue

        filename = parts[-1]
        parent = parent_node
        parent["children"].append(
            {
                "name": filename,
                "path": "/".join(parts),
                "type": "file",
                "size": record.size,
                "modified": record.updated_at.timestamp() if record.updated_at else None,
            }
        )

    def sort_children(node: Dict[str, Any]) -> None:
        node["children"].sort(
            key=lambda item: (item.get("type") != "directory", item.get("name", "").lower())
        )
        for child in node["children"]:
            if child.get("type") == "directory":
                sort_children(child)

    sort_children(root)
    return root




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
    base_path = _normalize_base_path(basePath)
    records = FilesService.list_by_prefix(db, user_id, base_path)
    tree = _build_tree_from_records(records, base_path)
    return {"children": tree.get("children", [])}


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
    base_path = _normalize_base_path(basePath)
    records = FilesService.search_by_name(db, user_id, query, base_path, limit=limit)
    items = []
    for record in records:
        rel_path = _relative_path(base_path, record.path)
        items.append({
            "name": Path(rel_path).name,
            "path": rel_path,
            "type": "file",
            "modified": record.updated_at.timestamp() if record.updated_at else None,
            "size": record.size,
        })
    return {"items": items}


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

    full_path = _full_path(base_path, path)
    bucket_key = _bucket_key(user_id, f"{full_path}/")
    FilesService.upsert_file(
        db,
        user_id,
        full_path,
        bucket_key=bucket_key,
        size=0,
        content_type=None,
        etag=None,
        category="folder",
    )
    return {"success": True}


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

    old_full_path = _full_path(base_path, old_path)
    parent = str(Path(old_path).parent) if Path(old_path).parent != Path(".") else ""
    new_rel = f"{parent}/{new_name}".strip("/")
    new_full_path = _full_path(base_path, new_rel)

    if FilesService.get_by_path(db, user_id, new_full_path):
        raise HTTPException(status_code=400, detail="An item with that name already exists")

    record = FilesService.get_by_path(db, user_id, old_full_path)
    if record:
        is_folder = record.category == "folder"
    else:
        prefix_records = FilesService.list_by_prefix(db, user_id, f"{old_full_path}/")
        if not prefix_records:
            raise HTTPException(status_code=404, detail="Item not found")
        is_folder = True

    if not is_folder:
        old_key = record.bucket_key
        new_key = _bucket_key(user_id, new_full_path)
        storage_backend.move_object(old_key, new_key)
        record.path = new_full_path
        record.bucket_key = new_key
        record.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": new_rel}

    records = FilesService.list_by_prefix(db, user_id, f"{old_full_path}/")
    for item in records:
        if item.category == "folder":
            item.path = item.path.replace(old_full_path, new_full_path, 1)
            item.bucket_key = _bucket_key(user_id, f"{item.path}/")
            item.updated_at = datetime.now(timezone.utc)
            continue
        old_key = item.bucket_key
        item.path = item.path.replace(old_full_path, new_full_path, 1)
        item.bucket_key = _bucket_key(user_id, item.path)
        item.updated_at = datetime.now(timezone.utc)
        storage_backend.move_object(old_key, item.bucket_key)
    db.commit()
    return {"success": True, "newPath": new_rel}


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

    full_path = _full_path(base_path, path)
    destination_path = _full_path(base_path, destination)
    filename = Path(path).name
    new_full_path = _full_path(base_path, f"{destination}/{filename}")

    if FilesService.get_by_path(db, user_id, new_full_path):
        raise HTTPException(status_code=400, detail="An item with that name already exists")

    record = FilesService.get_by_path(db, user_id, full_path)
    if record:
        is_folder = record.category == "folder"
    else:
        prefix_records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
        if not prefix_records:
            raise HTTPException(status_code=404, detail="Item not found")
        is_folder = True

    if not is_folder:
        old_key = record.bucket_key
        new_key = _bucket_key(user_id, new_full_path)
        storage_backend.move_object(old_key, new_key)
        record.path = new_full_path
        record.bucket_key = new_key
        record.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": _relative_path(base_path, new_full_path)}

    records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
    for item in records:
        if item.category == "folder":
            item.path = item.path.replace(full_path, new_full_path, 1)
            item.bucket_key = _bucket_key(user_id, f"{item.path}/")
            item.updated_at = datetime.now(timezone.utc)
            continue
        old_key = item.bucket_key
        item.path = item.path.replace(full_path, new_full_path, 1)
        item.bucket_key = _bucket_key(user_id, item.path)
        item.updated_at = datetime.now(timezone.utc)
        storage_backend.move_object(old_key, item.bucket_key)
    db.commit()
    return {"success": True, "newPath": _relative_path(base_path, new_full_path)}


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

    full_path = _full_path(base_path, path)
    record = FilesService.get_by_path(db, user_id, full_path)
    if record:
        storage_backend.delete_object(record.bucket_key)
        FilesService.mark_deleted(db, user_id, full_path)
        return {"success": True}

    records = FilesService.list_by_prefix(db, user_id, f"{full_path}/")
    if not records:
        raise HTTPException(status_code=404, detail="Item not found")

    for item in records:
        if item.category != "folder":
            storage_backend.delete_object(item.bucket_key)
        FilesService.mark_deleted(db, user_id, item.path)
    return {"success": True}


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
    full_path = _full_path(basePath, path)
    record = FilesService.get_by_path(db, user_id, full_path)
    if not record or record.category == "folder":
        raise HTTPException(status_code=404, detail="File not found")

    content = storage_backend.get_object(record.bucket_key)
    content_type = record.content_type or mimetypes.guess_type(path)[0] or "application/octet-stream"
    return Response(
        content,
        media_type=content_type,
        headers={"Content-Disposition": f'attachment; filename="{Path(path).name}"'},
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

    full_path = _full_path(basePath, path)
    record = FilesService.get_by_path(db, user_id, full_path)
    if not record or record.category == "folder":
        raise HTTPException(status_code=404, detail="File not found")

    content = storage_backend.get_object(record.bucket_key)
    if record.content_type and record.content_type.startswith("text/"):
        return {
            "content": content.decode("utf-8"),
            "name": Path(path).name,
            "path": path,
            "modified": record.updated_at.timestamp() if record.updated_at else None,
        }

    try:
        decoded = content.decode("utf-8")
        return {
            "content": decoded,
            "name": Path(path).name,
            "path": path,
            "modified": record.updated_at.timestamp() if record.updated_at else None,
        }
    except UnicodeDecodeError:
        raise HTTPException(status_code=400, detail="File is not a text file")


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

    full_path = _full_path(base_path, path)
    bucket_key = _bucket_key(user_id, full_path)
    data = content.encode("utf-8")
    storage_backend.put_object(bucket_key, data, content_type="text/plain")
    record = FilesService.upsert_file(
        db,
        user_id,
        full_path,
        bucket_key=bucket_key,
        size=len(data),
        content_type="text/plain",
        etag=None,
        category="file",
    )
    return {
        "success": True,
        "modified": record.updated_at.timestamp() if record.updated_at else None,
    }
