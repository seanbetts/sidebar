"""Typed contracts for the capability platform."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class CapabilityRegistryRecord:
    """Static code-backed capability metadata for one skill."""

    skill_id: str
    tier: str
    instruction_ref: str
    required_toolsets: tuple[str, ...] = ()
    tags: tuple[str, ...] = ()
    triggers: tuple[str, ...] = ()
    example_refs: tuple[str, ...] = ()
    token_estimate: int = 0


@dataclass(frozen=True)
class RuntimeCapabilityState:
    """Derived runtime state for a visible skill."""

    skill_id: str
    enabled: bool
    installed: bool
    availability_status: str
    availability_reason: str | None = None
    availability_remediation: dict[str, Any] | None = None


@dataclass(frozen=True)
class CapabilityResolverResult:
    """Resolver output split between selected and executable skills."""

    catalog_skill_ids: tuple[str, ...] = ()
    selected_skill_ids: tuple[str, ...] = ()
    executable_skill_ids: tuple[str, ...] = ()
    blocked_skills: tuple[dict[str, Any], ...] = ()


@dataclass(frozen=True)
class CapabilityLoaderResult:
    """Loader output for prompt/tool assembly."""

    selected_skill_ids: tuple[str, ...] = ()
    executable_skill_ids: tuple[str, ...] = ()
    loaded_instruction_refs: tuple[str, ...] = ()
    tool_definitions: tuple[dict[str, Any], ...] = field(default_factory=tuple)
