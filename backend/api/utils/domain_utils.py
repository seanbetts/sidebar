"""Domain utility helpers."""

from __future__ import annotations

from collections.abc import Callable

try:
    from publicsuffix2 import get_sld as _get_sld  # type: ignore[import-not-found]
except Exception:  # pragma: no cover - optional dependency
    _get_sld = None

_GetSld = Callable[[str], str | None]
get_sld: _GetSld | None = _get_sld


def extract_effective_domain(domain: str) -> str:
    """Return the registrable domain when possible."""
    host = domain.strip().lower().strip(".")
    if not host:
        return host
    host = host.split(":")[0]
    if get_sld is not None:
        sld = get_sld(host)
        if sld:
            return sld
    parts = host.split(".")
    if len(parts) >= 2:
        return ".".join(parts[-2:])
    return host
