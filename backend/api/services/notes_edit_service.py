"""Assistant-facing block-level note edit service."""

from __future__ import annotations

from copy import deepcopy
from typing import Any
from uuid import UUID

from sqlalchemy.orm import Session

from api.exceptions import BadRequestError, NoteNotFoundError
from api.models.note import Note
from api.services.notes_service import NotesService
from api.utils.timestamps import parse_client_timestamp


def _invalid_operation(message: str) -> BadRequestError:
    """Return a consistent edit-operation validation error."""
    return BadRequestError(f"Invalid note edit operation: {message}")


class NotesEditService:
    """Apply deterministic block-level edits to semantic notes."""

    @staticmethod
    def edit_note(
        db: Session,
        user_id: str,
        note_id: UUID,
        *,
        expected_updated_at: str,
        operations: list[dict[str, Any]],
    ) -> dict[str, str]:
        """Apply ordered edit operations and persist atomically."""
        note = NotesEditService._get_note(db, user_id, note_id)
        client_updated_at = parse_client_timestamp(
            expected_updated_at,
            field_name="expected_updated_at",
        )
        if client_updated_at is None:
            raise BadRequestError("expected_updated_at required")
        if not operations:
            raise _invalid_operation("operations must not be empty")

        working_document = deepcopy(note.document)
        if not isinstance(working_document, dict):
            raise BadRequestError("Invalid note document: document must be an object")
        blocks = working_document.get("blocks")
        if not isinstance(blocks, list):
            raise BadRequestError("Invalid note document: blocks must be a list")

        for operation in operations:
            NotesEditService._apply_operation(blocks, operation)

        updated_note = NotesService.update_note(
            db,
            user_id,
            note_id,
            document=working_document,
            client_updated_at=client_updated_at,
        )
        updated_at = (
            updated_note.updated_at.isoformat() if updated_note.updated_at else None
        )
        if updated_at is None:
            raise BadRequestError("Updated note is missing updated_at")
        return {
            "id": str(updated_note.id),
            "title": updated_note.title,
            "updated_at": updated_at,
        }

    @staticmethod
    def _get_note(db: Session, user_id: str, note_id: UUID) -> Note:
        """Return the live note targeted by the edit request."""
        note = NotesService.get_note(db, user_id, note_id, mark_opened=False)
        if note is None:
            raise NoteNotFoundError(str(note_id))
        return note

    @staticmethod
    def _apply_operation(
        blocks: list[dict[str, Any]],
        operation: dict[str, Any],
    ) -> None:
        """Apply one validated operation against the live block list."""
        if not isinstance(operation, dict):
            raise _invalid_operation("operation must be an object")

        operation_type = operation.get("type")
        if operation_type == "rename_note_title":
            NotesEditService._rename_note_title(blocks, operation)
            return
        if operation_type == "replace_block":
            NotesEditService._replace_block(blocks, operation)
            return
        if operation_type == "insert_blocks_after":
            NotesEditService._insert_blocks_after(blocks, operation)
            return
        if operation_type == "delete_block":
            NotesEditService._delete_block(blocks, operation)
            return
        raise _invalid_operation("unsupported operation type")

    @staticmethod
    def _rename_note_title(
        blocks: list[dict[str, Any]],
        operation: dict[str, Any],
    ) -> None:
        """Rewrite block 0 as the canonical title block."""
        if not blocks:
            raise _invalid_operation("note must contain a title block")
        text = operation.get("text")
        if not isinstance(text, str):
            raise _invalid_operation("rename_note_title text must be a string")
        if "\n" in text:
            raise _invalid_operation("rename_note_title text must be single-line")
        blocks[0] = {
            "type": "title",
            "content": [{"text": text, "marks": []}],
        }

    @staticmethod
    def _replace_block(
        blocks: list[dict[str, Any]],
        operation: dict[str, Any],
    ) -> None:
        """Replace one body block by absolute index."""
        index = NotesEditService._body_block_index(operation.get("index"), blocks)
        block = NotesEditService._body_block(operation.get("block"), field_name="block")
        blocks[index] = block

    @staticmethod
    def _insert_blocks_after(
        blocks: list[dict[str, Any]],
        operation: dict[str, Any],
    ) -> None:
        """Insert one or more body blocks after the target index."""
        index = NotesEditService._existing_block_index(operation.get("index"), blocks)
        raw_blocks = operation.get("blocks")
        if not isinstance(raw_blocks, list) or not raw_blocks:
            raise _invalid_operation(
                "insert_blocks_after blocks must be a non-empty list"
            )

        inserted_blocks = [
            NotesEditService._body_block(raw_block, field_name="blocks")
            for raw_block in raw_blocks
        ]
        blocks[index + 1 : index + 1] = inserted_blocks

    @staticmethod
    def _delete_block(
        blocks: list[dict[str, Any]],
        operation: dict[str, Any],
    ) -> None:
        """Delete one body block by absolute index."""
        index = NotesEditService._body_block_index(operation.get("index"), blocks)
        blocks.pop(index)

    @staticmethod
    def _existing_block_index(value: Any, blocks: list[dict[str, Any]]) -> int:
        """Validate an index against the current block list."""
        if not isinstance(value, int) or isinstance(value, bool):
            raise _invalid_operation("index must be an integer")
        if value < 0 or value >= len(blocks):
            raise _invalid_operation("index out of bounds")
        return value

    @staticmethod
    def _body_block_index(value: Any, blocks: list[dict[str, Any]]) -> int:
        """Validate an index that must target a body block."""
        index = NotesEditService._existing_block_index(value, blocks)
        if index == 0:
            raise _invalid_operation(
                "block 0 may only be modified by rename_note_title"
            )
        return index

    @staticmethod
    def _body_block(raw_block: Any, *, field_name: str) -> dict[str, Any]:
        """Validate one inserted or replacement block is a body block."""
        if not isinstance(raw_block, dict):
            raise _invalid_operation(f"{field_name} must contain block objects")
        block = deepcopy(raw_block)
        if block.get("type") == "title":
            raise _invalid_operation("body edit operations cannot use title blocks")
        return block
