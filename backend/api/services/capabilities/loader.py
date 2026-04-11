"""Load selected capability instructions, examples, and executable tools."""

from __future__ import annotations

import logging
from collections.abc import Callable
from pathlib import Path
from typing import Any

from api.config import settings
from api.services.capabilities.registry import CapabilityRegistry
from api.services.capabilities.types import CapabilityLoaderResult

logger = logging.getLogger(__name__)


class CapabilityLoaderService:
    """Materialize the small per-turn capability subset behind a cache."""

    _document_cache: dict[str, str] = {}

    @classmethod
    def load_for_turn(
        cls,
        *,
        selected_skill_ids: list[str] | tuple[str, ...] | None,
        executable_skill_ids: list[str] | tuple[str, ...] | None,
        tool_definition_resolver: (
            Callable[[list[str] | None], list[dict[str, Any]]] | None
        ) = None,
    ) -> CapabilityLoaderResult:
        """Load selected instructions/examples and executable tool definitions."""
        selected_ids = tuple(selected_skill_ids or ())
        executable_ids = tuple(executable_skill_ids or ())
        loaded_instruction_refs: list[str] = []
        loaded_instructions: list[dict[str, Any]] = []
        loaded_examples: list[dict[str, Any]] = []

        for skill_id in selected_ids:
            capability = CapabilityRegistry.get_capability(skill_id)
            if capability is None:
                continue

            if capability.instruction_ref:
                instruction_content = cls._load_document(capability.instruction_ref)
                loaded_instruction_refs.append(capability.instruction_ref)
                if instruction_content:
                    loaded_instructions.append(
                        {
                            "skill_id": capability.skill_id,
                            "ref": capability.instruction_ref,
                            "content": instruction_content,
                        }
                    )

            for example_ref in capability.example_refs:
                example_content = cls._load_document(example_ref)
                if not example_content:
                    continue
                loaded_examples.append(
                    {
                        "skill_id": capability.skill_id,
                        "ref": example_ref,
                        "content": example_content,
                    }
                )

        tool_definitions: tuple[dict[str, Any], ...] = ()
        if tool_definition_resolver is not None:
            tool_definitions = tuple(tool_definition_resolver(list(executable_ids)))

        return CapabilityLoaderResult(
            selected_skill_ids=selected_ids,
            executable_skill_ids=executable_ids,
            loaded_instruction_refs=tuple(loaded_instruction_refs),
            loaded_instructions=tuple(loaded_instructions),
            loaded_examples=tuple(loaded_examples),
            tool_definitions=tool_definitions,
        )

    @classmethod
    def _load_document(cls, ref: str) -> str | None:
        """Load and cache one capability document by stable reference."""
        if ref in cls._document_cache:
            return cls._document_cache[ref]

        path = cls._resolve_ref_path(ref)
        try:
            content = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            logger.warning("Capability document missing", extra={"ref": ref})
            return None
        except OSError:
            logger.warning("Capability document unreadable", extra={"ref": ref})
            return None

        normalized = cls._strip_frontmatter(content).strip()
        cls._document_cache[ref] = normalized
        return normalized

    @staticmethod
    def _resolve_ref_path(ref: str) -> Path:
        """Resolve a stable capability reference to a local file path."""
        relative_path = Path(ref)
        if relative_path.parts and relative_path.parts[0] == "skills":
            return (settings.skills_dir.parent / relative_path).resolve()
        return (settings.skills_dir / relative_path).resolve()

    @staticmethod
    def _strip_frontmatter(content: str) -> str:
        """Remove leading YAML frontmatter from SKILL.md documents."""
        if not content.startswith("---\n"):
            return content
        _, separator, remainder = content[4:].partition("\n---\n")
        return remainder if separator else content
