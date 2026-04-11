"""Guardrails for Apple notification authorization configuration."""

from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
APP_ENVIRONMENT_PUSH = (
    REPO_ROOT / "ios" / "sideBar" / "sideBar" / "App" / "AppEnvironment+Push.swift"
)
ONBOARDING_PERMISSION_REQUESTERS = (
    REPO_ROOT
    / "ios"
    / "sideBar"
    / "sideBar"
    / "Services"
    / "Permissions"
    / "OnboardingPermissionRequesters.swift"
)
NOTIFICATION_AUTHORIZATION_POLICY = (
    REPO_ROOT
    / "ios"
    / "sideBar"
    / "sideBar"
    / "Services"
    / "Permissions"
    / "NotificationAuthorizationPolicy.swift"
)


def test_runtime_push_permissions_request_visible_alert_authorization() -> None:
    contents = APP_ENVIRONMENT_PUSH.read_text(encoding="utf-8")

    assert "NotificationAuthorizationPolicy.visibleRemoteNotificationRequestOptions" in contents


def test_onboarding_notification_permissions_request_visible_alert_authorization() -> None:
    contents = ONBOARDING_PERMISSION_REQUESTERS.read_text(encoding="utf-8")

    assert "NotificationAuthorizationPolicy" in contents
    policy_contents = NOTIFICATION_AUTHORIZATION_POLICY.read_text(encoding="utf-8")
    assert ".alert" in policy_contents
    assert ".sound" in policy_contents
    assert ".badge" in policy_contents
