"""Files router for browsing workspace files."""
import os
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from api.auth import verify_bearer_token
from api.db.session import get_db
from api.models.note import Note
from typing import Dict, Any

router = APIRouter(prefix="/files", tags=["files"])

WORKSPACE_BASE = os.getenv("WORKSPACE_BASE", "/workspace")
H1_PATTERN = re.compile(r"^#\s+(.+)$", re.MULTILINE)


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


def extract_title(content: str, fallback: str) -> str:
    match = H1_PATTERN.search(content or "")
    if match:
        return match.group(1).strip()
    return fallback


def update_content_title(content: str, title: str) -> str:
    if H1_PATTERN.search(content or ""):
        return H1_PATTERN.sub(f"# {title}", content, count=1)
    return f"# {title}\n\n{content or ''}".strip() + "\n"


def build_notes_tree(notes: list[Note]) -> Dict[str, Any]:
    root = {"name": "notes", "path": "/", "type": "directory", "children": [], "expanded": False}
    index: Dict[str, Dict[str, Any]] = {"": root}

    for note in notes:
        if note.title == "✏️ Scratchpad":
            continue
        folder = (note.metadata_ or {}).get("folder") or ""
        folder_parts = [part for part in folder.split("/") if part]
        current_path = ""
        current_node = root

        for part in folder_parts:
            current_path = f"{current_path}/{part}" if current_path else part
            if current_path not in index:
                node = {
                    "name": part,
                    "path": f"folder:{current_path}",
                    "type": "directory",
                    "children": [],
                    "expanded": False
                }
                index[current_path] = node
                current_node["children"].append(node)
            current_node = index[current_path]

        current_node["children"].append({
            "name": f"{note.title}.md",
            "path": str(note.id),
            "type": "file",
            "modified": note.updated_at.timestamp() if note.updated_at else None
        })

    def sort_children(node: Dict[str, Any]) -> None:
        node["children"].sort(key=lambda item: (item.get("type") != "directory", item.get("name", "").lower()))
        for child in node["children"]:
            if child.get("type") == "directory":
                sort_children(child)

    sort_children(root)
    return root


def parse_note_id(value: str) -> uuid.UUID | None:
    try:
        return uuid.UUID(value)
    except (ValueError, TypeError):
        return None


@router.get("/tree")
async def get_file_tree(
    basePath: str = "documents",
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
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
    if basePath == "notes":
        notes = (
            db.query(Note)
            .filter(Note.deleted_at.is_(None))
            .order_by(Note.updated_at.desc())
            .all()
        )
        tree = build_notes_tree(notes)
        return {"children": tree.get("children", [])}

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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
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

    if base_path == "notes":
        if old_path.startswith("folder:"):
            old_folder = old_path.replace("folder:", "", 1)
            parent = "/".join(old_folder.split("/")[:-1])
            new_folder = f"{parent}/{new_name}".strip("/") if parent else new_name

            notes = db.query(Note).filter(Note.deleted_at.is_(None)).all()
            for note in notes:
                folder = (note.metadata_ or {}).get("folder") or ""
                if folder == old_folder or folder.startswith(f"{old_folder}/"):
                    updated_folder = folder.replace(old_folder, new_folder, 1)
                    note.metadata_ = {**(note.metadata_ or {}), "folder": updated_folder}
                    note.updated_at = datetime.now(timezone.utc)
            db.commit()
            return {"success": True, "newPath": f"folder:{new_folder}"}

        note_id = parse_note_id(old_path)
        if not note_id:
            raise HTTPException(status_code=400, detail="Invalid note id")

        note = db.query(Note).filter(Note.id == note_id, Note.deleted_at.is_(None)).first()
        if not note:
            raise HTTPException(status_code=404, detail="Item not found")

        title = Path(new_name).stem
        note.title = title
        note.content = update_content_title(note.content, title)
        note.updated_at = datetime.now(timezone.utc)
        db.commit()
        return {"success": True, "newPath": str(note.id)}

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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
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

    if base_path == "notes":
        if path.startswith("folder:"):
            folder = path.replace("folder:", "", 1)
            notes = db.query(Note).filter(Note.deleted_at.is_(None)).all()
            now = datetime.now(timezone.utc)
            for note in notes:
                note_folder = (note.metadata_ or {}).get("folder") or ""
                if note_folder == folder or note_folder.startswith(f"{folder}/"):
                    note.deleted_at = now
                    note.updated_at = now
            db.commit()
            return {"success": True}

        note_id = parse_note_id(path)
        if not note_id:
            raise HTTPException(status_code=400, detail="Invalid note id")

        note = db.query(Note).filter(Note.id == note_id, Note.deleted_at.is_(None)).first()
        if not note:
            raise HTTPException(status_code=404, detail="Item not found")

        now = datetime.now(timezone.utc)
        note.deleted_at = now
        note.updated_at = now
        db.commit()
        return {"success": True}

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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
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

    if basePath == "notes":
        note_id = parse_note_id(path)
        if not note_id:
            raise HTTPException(status_code=400, detail="Invalid note id")

        note = db.query(Note).filter(Note.id == note_id, Note.deleted_at.is_(None)).first()
        if not note:
            raise HTTPException(status_code=404, detail="File not found")

        note.last_opened_at = datetime.now(timezone.utc)
        db.commit()

        return {
            "content": note.content,
            "name": f"{note.title}.md",
            "path": str(note.id),
            "modified": note.updated_at.timestamp() if note.updated_at else None
        }

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
    user_id: str = Depends(verify_bearer_token),
    db: Session = Depends(get_db)
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

    if base_path == "notes":
        now = datetime.now(timezone.utc)
        note_id = parse_note_id(path)
        note = None

        if note_id:
            note = db.query(Note).filter(Note.id == note_id, Note.deleted_at.is_(None)).first()
            if not note:
                raise HTTPException(status_code=404, detail="File not found")

        if note:
            title = extract_title(content, note.title)
            note.title = title
            note.content = content
            note.updated_at = now
            db.commit()
            return {"success": True, "modified": note.updated_at.timestamp(), "id": str(note.id)}

        fallback_title = Path(path).stem
        title = extract_title(content, fallback_title)
        folder = Path(path).parent.as_posix()
        folder = "" if folder == "." else folder

        note = Note(
            title=title,
            content=content,
            metadata_={"folder": folder, "pinned": False},
            created_at=now,
            updated_at=now,
            last_opened_at=None,
            deleted_at=None
        )
        db.add(note)
        db.commit()
        return {"success": True, "modified": note.updated_at.timestamp(), "id": str(note.id)}

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
