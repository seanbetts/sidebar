"""Capability resolver that selects relevant and executable skills for a turn."""

from __future__ import annotations

from typing import Any

from api.services.capabilities.search import CapabilitySearchService


class CapabilityResolverService:
    """Resolve turn-relevant skills without loading instructions or tools."""

    _NOTE_KEYWORDS = {"note", "notes", "summarize", "summary"}
    _FILE_KEYWORDS = {"file", "files", "folder", "project", "workspace", "config"}

    @staticmethod
    def _catalog_capabilities(
        *,
        enabled_skill_ids: list[str],
        runtime_capabilities: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        runtime_by_id = {
            str(capability.get("skill_id")): capability
            for capability in runtime_capabilities
            if isinstance(capability.get("skill_id"), str)
        }
        return [
            runtime_by_id[skill_id]
            for skill_id in enabled_skill_ids
            if skill_id in runtime_by_id
        ]

    @classmethod
    def _deterministic_matches(
        cls,
        *,
        user_message: str,
        open_context: dict[str, Any] | None,
        catalog_capabilities: list[dict[str, Any]],
    ) -> list[str]:
        message_tokens = set(CapabilitySearchService._tokenize(user_message))
        visible_skill_ids = {
            str(capability.get("skill_id")) for capability in catalog_capabilities
        }
        selected: list[str] = []

        if (
            isinstance(open_context, dict)
            and open_context.get("note") is not None
            and "notes" in visible_skill_ids
            and message_tokens & cls._NOTE_KEYWORDS
        ):
            selected.append("notes")

        if (
            isinstance(open_context, dict)
            and open_context.get("file") is not None
            and "files" in visible_skill_ids
            and message_tokens & cls._FILE_KEYWORDS
        ):
            selected.append("files")

        return selected

    @staticmethod
    def _compact_blocked_skill(capability: dict[str, Any]) -> dict[str, Any]:
        return {
            "skill_id": str(capability["skill_id"]),
            "availability_status": capability.get("availability_status"),
            "availability_reason": capability.get("availability_reason"),
            "availability_remediation": capability.get("availability_remediation"),
        }

    @classmethod
    def resolve_for_turn(
        cls,
        *,
        user_message: str,
        enabled_skill_ids: list[str],
        runtime_capabilities: list[dict[str, Any]],
        open_context: dict[str, Any] | None = None,
        attachments: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Return visible, selected, executable, and blocked skill IDs."""
        _ = attachments
        catalog_capabilities = cls._catalog_capabilities(
            enabled_skill_ids=enabled_skill_ids,
            runtime_capabilities=runtime_capabilities,
        )
        catalog_skill_ids = [
            str(capability["skill_id"]) for capability in catalog_capabilities
        ]

        selected_skill_ids = cls._deterministic_matches(
            user_message=user_message,
            open_context=open_context,
            catalog_capabilities=catalog_capabilities,
        )
        if not selected_skill_ids:
            selected_skill_ids = CapabilitySearchService.rank_visible_skills(
                user_message=user_message,
                visible_capabilities=catalog_capabilities,
            )
        if not selected_skill_ids:
            selected_skill_ids = list(catalog_skill_ids)
        else:
            selected_set = set(selected_skill_ids)
            selected_skill_ids = [
                skill_id for skill_id in catalog_skill_ids if skill_id in selected_set
            ]

        selected_set = set(selected_skill_ids)
        blocked_skills = [
            cls._compact_blocked_skill(capability)
            for capability in catalog_capabilities
            if str(capability["skill_id"]) in selected_set
            and str(capability.get("availability_status", "ready")) != "ready"
        ]
        executable_skill_ids = [
            str(capability["skill_id"])
            for capability in catalog_capabilities
            if str(capability["skill_id"]) in selected_set
            and str(capability.get("availability_status", "ready")) == "ready"
        ]

        return {
            "catalog_skill_ids": catalog_skill_ids,
            "selected_skill_ids": selected_skill_ids,
            "executable_skill_ids": executable_skill_ids,
            "blocked_skills": blocked_skills,
            "blocked_skill_summaries": blocked_skills,
        }
