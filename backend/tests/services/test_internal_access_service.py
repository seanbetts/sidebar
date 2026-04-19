from api.services.internal_access_service import InternalAccessService


def test_can_access_internal_diagnostics_returns_false_when_disabled(monkeypatch):
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "false")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", "user-123")

    assert InternalAccessService.can_access_internal_diagnostics("user-123") is False


def test_can_access_internal_diagnostics_returns_true_for_allowlisted_user(
    monkeypatch,
):
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", " user-123 , user-456 ,, ")

    assert InternalAccessService.can_access_internal_diagnostics("user-123") is True


def test_can_access_internal_diagnostics_returns_false_for_non_allowlisted_user(
    monkeypatch,
):
    monkeypatch.setenv("INTERNAL_DIAGNOSTICS_ENABLED", "true")
    monkeypatch.setenv("INTERNAL_DIAGNOSTIC_USER_IDS", "user-123")

    assert InternalAccessService.can_access_internal_diagnostics("user-999") is False
