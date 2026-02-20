#!/usr/bin/env python3
"""Smoke-test AI provider/model matrix for a user in strict BYOK mode."""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace
from typing import Any

# Ensure backend package root is importable when running as a script.
BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

# Default local script environment for skills/tool loading.
os.environ.setdefault("SKILLS_DIR", str(BACKEND_ROOT / "skills"))
os.environ.setdefault("WORKSPACE_BASE", str(BACKEND_ROOT / ".tmp" / "smoke-workspace"))

from api.config import settings  # noqa: E402
from api.db.session import SessionLocal, set_session_user_id  # noqa: E402
from api.services.ai.gateway import AIProviderGateway  # noqa: E402
from api.services.ai.policy import AICapabilityUnavailableError  # noqa: E402
from api.services.ai.registry import AIProvider  # noqa: E402
from api.services.user_ai_provider_key_service import UserAIProviderKeyService  # noqa: E402


@dataclass
class CheckResult:
    """Single check result for summary output."""

    name: str
    ok: bool
    details: str


def _parse_providers(raw: str) -> list[AIProvider]:
    """Parse comma-separated providers."""
    values = [item.strip().lower() for item in raw.split(",") if item.strip()]
    parsed: list[AIProvider] = []
    for value in values:
        if value not in {"anthropic", "openai", "google"}:
            raise ValueError(f"Unsupported provider '{value}'")
        parsed.append(value)  # type: ignore[arg-type]
    return parsed


def _write_silence_wav(path: Path, *, duration_seconds: float = 0.5) -> None:
    """Create a short mono silence WAV file."""
    sample_rate = 16000
    frame_count = int(sample_rate * duration_seconds)
    silence = b"\x00\x00" * frame_count
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(silence)


async def _collect_chat_events(
    gateway: AIProviderGateway,
    *,
    provider: AIProvider,
    user_message: str,
    db,
    user_id: str,
    provider_key_lookup,
    allowed_skills: list[str] | None,
) -> list[dict[str, Any]]:
    """Run one chat stream and collect all events."""
    events: list[dict[str, Any]] = []
    async for event in gateway.stream_chat_with_tools(
        message=user_message,
        conversation_history=[],
        system_prompt="You are a concise assistant.",
        allowed_skills=allowed_skills,
        tool_context={
            "db": db,
            "user_id": user_id,
            "open_context": {},
            "attachments": [],
            "user_agent": "smoke-test-script",
        },
        settings_record=SimpleNamespace(ai_primary_provider=provider),
        provider_key_lookup=provider_key_lookup,
    ):
        events.append(event)
    return events


def _has_stream_error(events: list[dict[str, Any]]) -> str | None:
    """Return first stream error text, if present."""
    for event in events:
        if event.get("type") == "error":
            error = event.get("error")
            return str(error) if error else "Unknown stream error"
    return None


def _token_text(events: list[dict[str, Any]]) -> str:
    """Concatenate token event text."""
    return "".join(
        event.get("content", "") for event in events if event.get("type") == "token"
    ).strip()


def _run_openai_transcription_live(*, api_key: str, model: str) -> str:
    """Run a live OpenAI transcription against a short silence WAV clip."""
    openai_module = __import__("openai")
    client = openai_module.OpenAI(api_key=api_key)
    with tempfile.TemporaryDirectory(prefix="sidebar-stt-smoke-") as tmp_dir:
        wav_path = Path(tmp_dir) / "silence.wav"
        _write_silence_wav(wav_path)
        with wav_path.open("rb") as wav_file:
            result = client.audio.transcriptions.create(
                model=model,
                file=wav_file,
                response_format="text",
            )
    return str(result).strip()


def _print_result(result: CheckResult) -> None:
    """Print one check line."""
    status = "PASS" if result.ok else "FAIL"
    print(f"[{status}] {result.name} - {result.details}")


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description=(
            "Live smoke-test provider/model paths for chat, titles, tools, and "
            "OpenAI transcription using a user's BYOK keys."
        )
    )
    parser.add_argument(
        "--user-id",
        default=settings.default_user_id,
        help="Target user ID (defaults to settings.default_user_id).",
    )
    parser.add_argument(
        "--providers",
        default="anthropic,openai,google",
        help="Comma-separated providers to test.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only resolve models/keys without live provider requests.",
    )
    parser.add_argument(
        "--skip-tools",
        action="store_true",
        help="Skip tool-orchestration checks.",
    )
    parser.add_argument(
        "--skip-live-transcription",
        action="store_true",
        help="Skip live OpenAI transcription call (still resolves transcription model).",
    )
    args = parser.parse_args()

    try:
        providers = _parse_providers(args.providers)
    except ValueError as error:
        print(f"Invalid --providers value: {error}")
        return 2

    results: list[CheckResult] = []
    gateway = AIProviderGateway(settings)

    try:
        with SessionLocal() as db:
            set_session_user_id(db, args.user_id)

            def provider_key_lookup(provider: AIProvider) -> str | None:
                return UserAIProviderKeyService.get_active_key(db, args.user_id, provider)

            for provider in providers:
                key_exists = UserAIProviderKeyService.has_active_key(
                    db, args.user_id, provider
                )
                results.append(
                    CheckResult(
                        name=f"{provider}: key",
                        ok=key_exists,
                        details="active key found"
                        if key_exists
                        else "missing active key",
                    )
                )
                if not key_exists:
                    continue

                try:
                    chat_resolution = gateway.resolve_chat(
                        settings_record=SimpleNamespace(ai_primary_provider=provider),
                        provider_key_lookup=provider_key_lookup,
                    )
                    results.append(
                        CheckResult(
                            name=f"{provider}: chat model",
                            ok=True,
                            details=chat_resolution.model,
                        )
                    )
                except Exception as error:  # pragma: no cover - smoke script resilience
                    results.append(
                        CheckResult(
                            name=f"{provider}: chat model",
                            ok=False,
                            details=str(error),
                        )
                    )
                    continue

                if not args.dry_run:
                    events = asyncio.run(
                        _collect_chat_events(
                            gateway,
                            provider=provider,
                            user_message="Reply with exactly: smoke-ok",
                            db=db,
                            user_id=args.user_id,
                            provider_key_lookup=provider_key_lookup,
                            allowed_skills=[],
                        )
                    )
                    chat_error = _has_stream_error(events)
                    token_text = _token_text(events)
                    results.append(
                        CheckResult(
                            name=f"{provider}: chat live",
                            ok=chat_error is None and bool(token_text),
                            details=token_text if chat_error is None else chat_error,
                        )
                    )

                try:
                    title_result = asyncio.run(
                        gateway.generate_title(
                            user_message="Plan sprint goals",
                            assistant_message="Let's define top priorities",
                            settings_record=SimpleNamespace(ai_primary_provider=provider),
                            provider_key_lookup=provider_key_lookup,
                        )
                    )
                    title_text = (title_result.raw_title or "").strip()
                    results.append(
                        CheckResult(
                            name=f"{provider}: title model",
                            ok=bool(title_text),
                            details=f"{title_result.provider} -> {title_text[:80]}",
                        )
                    )
                except Exception as error:  # pragma: no cover - smoke script resilience
                    results.append(
                        CheckResult(
                            name=f"{provider}: title model",
                            ok=False,
                            details=str(error),
                        )
                    )

                if not args.dry_run and not args.skip_tools:
                    tool_events = asyncio.run(
                        _collect_chat_events(
                            gateway,
                            provider=provider,
                            user_message=(
                                "You must call the Generate_Prompts tool once before "
                                "replying. After tool execution, reply with exactly: tool-ok"
                            ),
                            db=db,
                            user_id=args.user_id,
                            provider_key_lookup=provider_key_lookup,
                            allowed_skills=["prompt-preview"],
                        )
                    )
                    tool_error = _has_stream_error(tool_events)
                    tool_call_count = sum(
                        1 for event in tool_events if event.get("type") == "tool_call"
                    )
                    results.append(
                        CheckResult(
                            name=f"{provider}: tool orchestration",
                            ok=tool_error is None and tool_call_count > 0,
                            details=(
                                f"tool_calls={tool_call_count}"
                                if tool_error is None
                                else tool_error
                            ),
                        )
                    )

                if provider == "openai":
                    try:
                        transcription = gateway.resolve_transcription(
                            settings_record=SimpleNamespace(ai_primary_provider="openai"),
                            requested_model=None,
                            provider_key_lookup=provider_key_lookup,
                        )
                        results.append(
                            CheckResult(
                                name="openai: transcription model",
                                ok=True,
                                details=transcription.model,
                            )
                        )
                        if not args.dry_run and not args.skip_live_transcription:
                            text = _run_openai_transcription_live(
                                api_key=transcription.api_key,
                                model=transcription.model,
                            )
                            results.append(
                                CheckResult(
                                    name="openai: transcription live",
                                    ok=True,
                                    details=text[:80] if text else "(empty text)",
                                )
                            )
                    except Exception as error:  # pragma: no cover - smoke script resilience
                        results.append(
                            CheckResult(
                                name="openai: transcription",
                                ok=False,
                                details=str(error),
                            )
                        )
                else:
                    try:
                        gateway.resolve_transcription(
                            settings_record=SimpleNamespace(ai_primary_provider=provider),
                            requested_model=None,
                            provider_key_lookup=provider_key_lookup,
                        )
                        results.append(
                            CheckResult(
                                name=f"{provider}: transcription unsupported guard",
                                ok=False,
                                details="expected unsupported capability error, got success",
                            )
                        )
                    except AICapabilityUnavailableError:
                        results.append(
                            CheckResult(
                                name=f"{provider}: transcription unsupported guard",
                                ok=True,
                                details="correctly blocked",
                            )
                        )
    except Exception as error:  # pragma: no cover - smoke script resilience
        print("Failed to open DB session for smoke test.")
        print(f"DATABASE_URL={settings.database_url}")
        print(
            "Tip: run in your normal backend environment (Doppler/docker/dev shell) "
            "where DATABASE_URL points to a reachable Postgres host."
        )
        print(f"Error: {error}")
        return 2

    print("\nAI provider matrix smoke test")
    print(f"user_id={args.user_id}")
    print(f"providers={','.join(providers)}")
    print(f"mode={'dry-run' if args.dry_run else 'live'}")
    print("")

    for result in results:
        _print_result(result)

    failed = [result for result in results if not result.ok]
    print("")
    print(
        f"Summary: {len(results) - len(failed)} passed, {len(failed)} failed, {len(results)} total"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
