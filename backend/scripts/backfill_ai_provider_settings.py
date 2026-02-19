#!/usr/bin/env python3
"""Backfill existing users to explicit AI provider settings for BYOK rollout."""

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

# Settings requires an Anthropic key value, even when not used by this script.
os.environ.setdefault("ANTHROPIC_API_KEY", "local-dev-placeholder")

from api.db.session import SessionLocal  # noqa: E402
from api.services.ai.registry import AIProvider, VALID_AI_PROVIDERS  # noqa: E402
from api.services.user_ai_provider_key_service import UserAIProviderKeyService  # noqa: E402
from api.services.user_settings_service import UserSettingsService  # noqa: E402


PROVIDER_ENV_VARS: dict[AIProvider, str] = {
    "anthropic": "ANTHROPIC_API_KEY",
    "openai": "OPENAI_API_KEY",
    "google": "GOOGLE_API_KEY",
}


@dataclass
class BackfillOutcome:
    """Record per-user backfill actions."""

    user_id: str
    selected_provider: str | None
    seeded_providers: list[str]
    status: str
    note: str


def _is_valid_provider(value: str | None) -> bool:
    return isinstance(value, str) and value in VALID_AI_PROVIDERS


def _active_key_providers(db, user_id: str) -> list[AIProvider]:
    providers: list[AIProvider] = []
    for provider in VALID_AI_PROVIDERS:
        if UserAIProviderKeyService.has_active_key(db, user_id, provider):
            providers.append(provider)
    return providers


def _seed_managed_keys(db, user_id: str, *, apply: bool) -> list[str]:
    seeded: list[str] = []
    for provider, env_var in PROVIDER_ENV_VARS.items():
        raw_key = os.getenv(env_var)
        if not isinstance(raw_key, str) or not raw_key.strip():
            continue
        seeded.append(provider)
        if apply:
            UserAIProviderKeyService.upsert_key(
                db,
                user_id=user_id,
                provider=provider,
                api_key=raw_key.strip(),
            )
    return seeded


def _resolve_selected_provider(
    *,
    existing_primary: str | None,
    providers_with_keys: list[AIProvider],
) -> tuple[str | None, str]:
    if "anthropic" in providers_with_keys:
        return "anthropic", "Selected anthropic for strict BYOK chat support"

    if _is_valid_provider(existing_primary) and existing_primary in providers_with_keys:
        return (
            existing_primary,
            "No anthropic key; retained existing primary provider",
        )

    if providers_with_keys:
        selected = providers_with_keys[0]
        return (
            selected,
            "No anthropic key; selected an available provider",
        )

    return None, "No provider key available; user not updated"


def _discover_user_ids(db, explicit_user_ids: list[str]) -> list[str]:
    user_ids = {user_id.strip() for user_id in explicit_user_ids if user_id.strip()}

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


def run_backfill(*, apply: bool, seed_from_managed: bool, user_ids: list[str]) -> int:
    db = SessionLocal()
    outcomes: list[BackfillOutcome] = []
    try:
        resolved_user_ids = _discover_user_ids(db, user_ids)
        if not resolved_user_ids:
            print("No user IDs discovered; nothing to backfill.")
            return 0

        for user_id in resolved_user_ids:
            seeded_providers: list[str] = []
            if seed_from_managed:
                seeded_providers = _seed_managed_keys(db, user_id, apply=apply)

            settings_record = UserSettingsService.get_settings(db, user_id)
            existing_primary = (
                settings_record.ai_primary_provider
                if settings_record and isinstance(settings_record.ai_primary_provider, str)
                else None
            )
            providers_with_keys = _active_key_providers(db, user_id)
            selected_provider, note = _resolve_selected_provider(
                existing_primary=existing_primary,
                providers_with_keys=providers_with_keys,
            )

            if selected_provider is None:
                outcomes.append(
                    BackfillOutcome(
                        user_id=user_id,
                        selected_provider=None,
                        seeded_providers=seeded_providers,
                        status="skipped",
                        note=note,
                    )
                )
                continue

            if apply:
                UserSettingsService.upsert_settings(
                    db,
                    user_id,
                    ai_primary_provider=selected_provider,
                )

            outcomes.append(
                BackfillOutcome(
                    user_id=user_id,
                    selected_provider=selected_provider,
                    seeded_providers=seeded_providers,
                    status="updated" if apply else "planned",
                    note=note,
                )
            )

        print(f"mode={'apply' if apply else 'dry-run'}")
        for outcome in outcomes:
            seeded = ",".join(outcome.seeded_providers) if outcome.seeded_providers else "-"
            provider = outcome.selected_provider or "-"
            print(
                f"user_id={outcome.user_id} status={outcome.status} "
                f"provider={provider} seeded={seeded} note={outcome.note}"
            )
        return 0
    finally:
        db.close()


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Backfill ai_primary_provider for existing users."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist updates (default is dry-run).",
    )
    parser.add_argument(
        "--seed-from-managed",
        action="store_true",
        help="Copy configured managed provider env keys into user BYOK records first.",
    )
    parser.add_argument(
        "--user-id",
        action="append",
        default=[],
        help="Optional user ID to include (can be passed multiple times).",
    )
    args = parser.parse_args()
    return run_backfill(
        apply=bool(args.apply),
        seed_from_managed=bool(args.seed_from_managed),
        user_ids=list(args.user_id),
    )


if __name__ == "__main__":
    raise SystemExit(main())
