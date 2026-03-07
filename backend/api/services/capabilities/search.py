"""In-memory capability search over visible skills."""

from __future__ import annotations

import re
from collections.abc import Iterable
from typing import Any

_TOKEN_RE = re.compile(r"[a-z0-9]+")


class CapabilitySearchService:
    """Rank visible skills against a turn using lightweight token overlap."""

    @staticmethod
    def _tokenize(*values: str) -> list[str]:
        tokens: list[str] = []
        for value in values:
            tokens.extend(_TOKEN_RE.findall(value.lower()))
        return tokens

    @classmethod
    def rank_visible_skills(
        cls,
        *,
        user_message: str,
        visible_capabilities: Iterable[dict[str, Any]],
    ) -> list[str]:
        """Return visible skill IDs ordered by relevance to the user message."""
        query_tokens = set(cls._tokenize(user_message))
        if not query_tokens:
            return []

        scored: list[tuple[int, int, str]] = []
        for index, capability in enumerate(visible_capabilities):
            skill_id = str(capability.get("skill_id", "")).strip()
            if not skill_id:
                continue
            search_tokens = set(
                cls._tokenize(
                    skill_id.replace("-", " "),
                    str(capability.get("name", "")),
                    str(capability.get("description", "")),
                    " ".join(
                        str(item)
                        for item in capability.get("tags", [])
                        if isinstance(item, str)
                    ),
                    " ".join(
                        str(item)
                        for item in capability.get("triggers", [])
                        if isinstance(item, str)
                    ),
                )
            )
            score = len(query_tokens & search_tokens)
            if score > 0:
                scored.append((score, -index, skill_id))

        scored.sort(reverse=True)
        return [skill_id for _score, _index, skill_id in scored]
