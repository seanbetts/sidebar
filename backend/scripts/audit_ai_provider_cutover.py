#!/usr/bin/env python3
"""Audit strict-BYOK readiness before removing managed provider env keys."""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path

from sqlalchemy import text

# Ensure backend package root is importable when running as a script.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

# Keep script behavior deterministic if local env omits legacy provider vars.
os.environ.setdefault("ANTHROPIC_API_KEY", "local-dev-placeholder")

from api.db.session import SessionLocal, set_session_user_id  # noqa: E402
from api.services.ai.registry import AIProvider, VALID_AI_PROVIDERS  # noqa: E402
from api.services.user_ai_provider_key_service import UserAIProviderKeyService  # noqa: E402
from api.services.user_settings_service import UserSettingsService  # noqa: E402


@dataclass(frozen=True)
class UserAuditResult:
    """Per-user strict-BYOK cutover audit result."""

    user_id: str
    primary_provider: str | None
    active_key_providers: list[str]
    issues: list[str]

    @property
    def ok(self) -> bool:
        return len(self.issues) == 0


def _parse_providers(raw: str | None) -> list[AIProvider]:
    """Parse comma-separated providers and validate values."""
    if not raw:
        return []
    parsed: list[AIProvider] = []
    for item in raw.split(","):
        candidate = item.strip().lower()
        if not candidate:
            continue
        if candidate not in VALID_AI_PROVIDERS:
            allowed = ",".join(VALID_AI_PROVIDERS)
            raise ValueError(f"Invalid provider '{candidate}'. Allowed: {allowed}")
        parsed.append(candidate)  # type: ignore[arg-type]
    return parsed


def _discover_user_ids(db, explicit_user_ids: list[str]) -> list[str]:
    """Discover users from settings and provider-key tables."""
    user_ids = {user_id.strip() for user_id in explicit_user_ids if user_id.strip()}
    if user_ids:
        return sorted(user_ids)

    settings_ids = db.execute(
        text("SELECT DISTINCT user_id FROM user_settings WHERE user_id IS NOT NULL")
    ).fetchall()
    for row in settings_ids:
        user_ids.add(row.user_id)

    key_ids = db.execute(
        text(
            "SELECT DISTINCT user_id FROM user_ai_provider_keys "
            "WHERE user_id IS NOT NULL AND deleted_at IS NULL"
        )
    ).fetchall()
    for row in key_ids:
        user_ids.add(row.user_id)

    return sorted(user_ids)


def _active_key_providers(db, user_id: str) -> list[str]:
    """Return providers with active saved BYOK keys for a user."""
    providers: list[str] = []
    for provider in VALID_AI_PROVIDERS:
        if UserAIProviderKeyService.has_active_key(db, user_id, provider):
            providers.append(provider)
    return providers


def _normalized_primary_provider(user_id: str, settings_record) -> str | None:
    """Return normalized primary provider if valid, otherwise None."""
    raw_primary = (
        settings_record.ai_primary_provider
        if settings_record and isinstance(settings_record.ai_primary_provider, str)
        else None
    )
    if raw_primary is None:
        return None
    candidate = raw_primary.strip().lower()
    if candidate in VALID_AI_PROVIDERS:
        return candidate
    print(
        f"warning: user_id={user_id} has invalid ai_primary_provider={raw_primary!r}; "
        "treating as unset"
    )
    return None


def _audit_user(
    db,
    *,
    user_id: str,
    required_providers: list[AIProvider],
) -> UserAuditResult:
    """Audit one user for strict-BYOK readiness."""
    settings_record = UserSettingsService.get_settings(db, user_id)
    primary_provider = _normalized_primary_provider(user_id, settings_record)
    active_key_providers = _active_key_providers(db, user_id)

    issues: list[str] = []
    if primary_provider is None:
        issues.append("missing ai_primary_provider")
    elif primary_provider not in active_key_providers:
        issues.append(f"missing active key for primary provider '{primary_provider}'")

    for provider in required_providers:
        if provider not in active_key_providers:
            issues.append(f"missing required provider key '{provider}'")

    return UserAuditResult(
        user_id=user_id,
        primary_provider=primary_provider,
        active_key_providers=active_key_providers,
        issues=issues,
    )


def run_audit(*, user_ids: list[str], required_providers: list[AIProvider]) -> int:
    """Run cutover audit across target users."""
    with SessionLocal() as db:
        resolved_user_ids = _discover_user_ids(db, user_ids)
        if not resolved_user_ids:
            print("No user IDs discovered; nothing to audit.")
            return 0

        results: list[UserAuditResult] = []
        for user_id in resolved_user_ids:
            set_session_user_id(db, user_id)
            results.append(
                _audit_user(
                    db,
                    user_id=user_id,
                    required_providers=required_providers,
                )
            )

    print("AI provider cutover audit")
    print(
        f"users={len(results)} required_providers={','.join(required_providers) or '-'}"
    )
    print("")

    failing = [result for result in results if not result.ok]
    for result in results:
        status = "PASS" if result.ok else "FAIL"
        primary = result.primary_provider or "-"
        providers = (
            ",".join(result.active_key_providers)
            if result.active_key_providers
            else "-"
        )
        issues = " | ".join(result.issues) if result.issues else "-"
        print(
            f"[{status}] user_id={result.user_id} primary={primary} "
            f"active_keys={providers} issues={issues}"
        )

    print("")
    print(
        "Summary: "
        f"{len(results) - len(failing)} passed, {len(failing)} failed, {len(results)} total"
    )
    return 1 if failing else 0


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description=(
            "Audit strict-BYOK readiness before removing managed provider "
            "environment keys."
        )
    )
    parser.add_argument(
        "--user-id",
        action="append",
        default=[],
        help="Optional user ID to include (can be passed multiple times).",
    )
    parser.add_argument(
        "--required-providers",
        default="",
        help=(
            "Optional comma-separated providers that must have active keys "
            "for each audited user."
        ),
    )
    args = parser.parse_args()

    try:
        required_providers = _parse_providers(args.required_providers)
    except ValueError as error:
        print(f"Invalid --required-providers value: {error}")
        return 2

    return run_audit(
        user_ids=list(args.user_id),
        required_providers=required_providers,
    )


if __name__ == "__main__":
    raise SystemExit(main())
