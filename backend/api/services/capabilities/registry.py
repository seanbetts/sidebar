"""Static capability registry."""

from __future__ import annotations

from api.services.capabilities.types import CapabilityRegistryRecord
from api.services.tools.skill_metadata import (
    EXPOSED_SKILLS,
    get_example_refs,
    get_instruction_ref,
    get_required_toolsets,
    get_skill_tags,
    get_skill_tier,
    get_skill_token_estimate,
    get_skill_triggers,
)


class CapabilityRegistry:
    """Return code-backed capability records without DB access."""

    @staticmethod
    def list_capabilities() -> list[CapabilityRegistryRecord]:
        """Return all exposed capability records."""
        return [
            CapabilityRegistryRecord(
                skill_id=skill_id,
                tier=get_skill_tier(skill_id),
                instruction_ref=get_instruction_ref(skill_id),
                required_toolsets=tuple(get_required_toolsets(skill_id)),
                tags=tuple(get_skill_tags(skill_id)),
                triggers=tuple(get_skill_triggers(skill_id)),
                example_refs=tuple(get_example_refs(skill_id)),
                token_estimate=get_skill_token_estimate(skill_id),
            )
            for skill_id in sorted(EXPOSED_SKILLS)
        ]

    @staticmethod
    def get_capability(skill_id: str) -> CapabilityRegistryRecord | None:
        """Return one capability record by skill ID."""
        for record in CapabilityRegistry.list_capabilities():
            if record.skill_id == skill_id:
                return record
        return None
