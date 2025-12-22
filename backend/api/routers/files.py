"""Files router for browsing workspace files."""
import os
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from api.auth import verify_bearer_token
from typing import List, Dict, Any

router = APIRouter(prefix="/files", tags=["files"])

WORKSPACE_BASE = os.getenv("WORKSPACE_BASE", "/workspace")


def build_file_tree(path: Path, base_path: Path = None) -> Dict[str, Any]:
    """Recursively build a file tree structure."""
    if base_path is None:
        base_path = path

    if not path.exists():
        return {
            "name": path.name or base_path.name,
            "path": str(path),
            "type": "directory",
            "children": []
        }

    name = path.name or base_path.name
    relative_path = str(path.relative_to(base_path)) if path != base_path else "/"

    if path.is_file():
        return {
            "name": name,
            "path": relative_path,
            "type": "file",
            "size": path.stat().st_size,
            "modified": path.stat().st_mtime
        }

    # Directory
    children = []
    try:
        for item in sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower())):
            # Skip hidden files and common excludes
            if item.name.startswith('.'):
                continue
            if item.name in ['__pycache__', 'node_modules', '.git']:
                continue

            children.append(build_file_tree(item, base_path))
    except PermissionError:
        pass

    return {
        "name": name,
        "path": relative_path,
        "type": "directory",
        "children": children,
        "expanded": False
    }


@router.get("/tree")
async def get_file_tree(
    basePath: str = "documents",
    user_id: str = Depends(verify_bearer_token)
):
    """
    Get the file tree for a subdirectory within workspace.

    Args:
        base_path: Subdirectory within workspace (e.g., "documents", "notes")

    Returns:
        {
            "children": [...]  # Direct children of the base_path folder
        }
    """
    # Construct the full path
    workspace_path = Path(WORKSPACE_BASE) / basePath

    # Create directory if it doesn't exist
    if not workspace_path.exists():
        workspace_path.mkdir(parents=True, exist_ok=True)

    tree = build_file_tree(workspace_path)

    # Return the children directly, not the root folder itself
    return {"children": tree.get("children", [])}


@router.post("/rename")
async def rename_file_or_folder(
    request: dict,
    user_id: str = Depends(verify_bearer_token)
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

    workspace_path = Path(WORKSPACE_BASE) / base_path
    old_full_path = workspace_path / old_path

    if not old_full_path.exists():
        raise HTTPException(status_code=404, detail="Item not found")

    # Construct new path (same parent directory, new name)
    new_full_path = old_full_path.parent / new_name

    if new_full_path.exists():
        raise HTTPException(status_code=400, detail="An item with that name already exists")

    try:
        old_full_path.rename(new_full_path)
        return {"success": True, "newPath": str(new_full_path.relative_to(workspace_path))}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to rename: {str(e)}")


@router.post("/delete")
async def delete_file_or_folder(
    request: dict,
    user_id: str = Depends(verify_bearer_token)
):
    """
    Delete a file or folder within workspace.

    Body:
        {
            "basePath": "documents",
            "path": "relative/path/to/item"
        }
    """
    import shutil

    base_path = request.get("basePath", "documents")
    path = request.get("path", "")

    if not path or path == "/":
        raise HTTPException(status_code=400, detail="Cannot delete root directory")

    workspace_path = Path(WORKSPACE_BASE) / base_path
    full_path = workspace_path / path

    if not full_path.exists():
        raise HTTPException(status_code=404, detail="Item not found")

    # Ensure we're not deleting outside workspace
    try:
        full_path.relative_to(workspace_path)
    except ValueError:
        raise HTTPException(status_code=403, detail="Access denied")

    try:
        if full_path.is_dir():
            shutil.rmtree(full_path)
        else:
            full_path.unlink()
        return {"success": True}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete: {str(e)}")


@router.get("/content")
async def get_file_content(
    basePath: str = "notes",
    path: str = "",
    user_id: str = Depends(verify_bearer_token)
):
    """
    Get the content of a file.

    Query params:
        basePath: Subdirectory within workspace (e.g., "notes", "documents")
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

    workspace_path = Path(WORKSPACE_BASE) / basePath
    full_path = workspace_path / path

    # Security: Ensure path is within workspace
    try:
        full_path.relative_to(workspace_path)
    except ValueError:
        raise HTTPException(status_code=403, detail="Access denied")

    if not full_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    if not full_path.is_file():
        raise HTTPException(status_code=400, detail="Path is not a file")

    try:
        content = full_path.read_text(encoding='utf-8')
        return {
            "content": content,
            "name": full_path.name,
            "path": str(full_path.relative_to(workspace_path)),
            "modified": full_path.stat().st_mtime
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to read file: {str(e)}")


@router.post("/content")
async def update_file_content(
    request: dict,
    user_id: str = Depends(verify_bearer_token)
):
    """
    Update the content of a file.

    Body:
        {
            "basePath": "notes",
            "path": "relative/path/file.md",
            "content": "new content..."
        }

    Returns:
        {
            "success": true,
            "modified": 1234567890
        }
    """
    base_path = request.get("basePath", "notes")
    path = request.get("path", "")
    content = request.get("content", "")

    if not path:
        raise HTTPException(status_code=400, detail="path required")

    workspace_path = Path(WORKSPACE_BASE) / base_path
    full_path = workspace_path / path

    # Security: Ensure path is within workspace
    try:
        full_path.relative_to(workspace_path)
    except ValueError:
        raise HTTPException(status_code=403, detail="Access denied")

    # Create parent directories if needed
    full_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        full_path.write_text(content, encoding='utf-8')
        return {
            "success": True,
            "modified": full_path.stat().st_mtime
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to write file: {str(e)}")
