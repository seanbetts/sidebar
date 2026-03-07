"""Capability-platform service helpers."""

from __future__ import annotations

from importlib import import_module
from typing import Any

__all__ = [
    "CapabilityLoaderResult",
    "CapabilityRegistry",
    "CapabilityRegistryRecord",
    "CapabilityResolverResult",
    "RuntimeCapabilityState",
    "SkillStateService",
]


def __getattr__(name: str) -> Any:
    """Resolve capability exports lazily to avoid package import cycles."""
    module_map = {
        "CapabilityRegistry": "api.services.capabilities.registry",
        "SkillStateService": "api.services.capabilities.skill_state_service",
        "CapabilityRegistryRecord": "api.services.capabilities.types",
        "RuntimeCapabilityState": "api.services.capabilities.types",
        "CapabilityResolverResult": "api.services.capabilities.types",
        "CapabilityLoaderResult": "api.services.capabilities.types",
    }
    module_name = module_map.get(name)
    if module_name is None:
        raise AttributeError(name)
    module = import_module(module_name)
    return getattr(module, name)
