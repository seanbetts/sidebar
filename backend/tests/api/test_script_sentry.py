"""Tests for shared Sentry bootstrap helpers."""

from api.services import script_sentry


def test_resolve_sentry_environment_normalizes_known_aliases() -> None:
    assert script_sentry.resolve_sentry_environment("prod") == "production"
    assert script_sentry.resolve_sentry_environment("production") == "production"
    assert script_sentry.resolve_sentry_environment(" local ") == "local"
    assert script_sentry.resolve_sentry_environment("") is None


def test_initialize_script_sentry_uses_canonical_environment(monkeypatch) -> None:
    init_calls: list[dict[str, object]] = []
    tags: dict[str, str] = {}

    class _Scope:
        def set_tag(self, key: str, value: str) -> None:
            tags[key] = value

    monkeypatch.setattr(
        script_sentry.settings, "sentry_dsn", "https://example@sentry.io/123"
    )
    monkeypatch.setattr(script_sentry.settings, "sentry_traces_sample_rate", 0.25)
    monkeypatch.setattr(script_sentry.settings, "sentry_profiles_sample_rate", 0.5)
    monkeypatch.setattr(script_sentry.settings, "app_env", "prod")
    monkeypatch.setattr(script_sentry, "_sentry_initialized", False)
    monkeypatch.setattr(
        script_sentry.sentry_sdk, "init", lambda **kwargs: init_calls.append(kwargs)
    )
    monkeypatch.setattr(script_sentry.sentry_sdk, "get_current_scope", lambda: _Scope())

    initialized = script_sentry.initialize_script_sentry("notes.save_note_document")

    assert initialized is True
    assert init_calls[0]["environment"] == "production"
    assert tags == {
        "process_type": "script",
        "script_name": "notes.save_note_document",
    }
