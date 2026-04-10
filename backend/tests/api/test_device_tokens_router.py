from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_device_tokens_register_and_disable(test_client):
    response = test_client.post(
        "/api/v1/device-tokens",
        headers=_auth_headers(),
        json={
            "token": "device-token-123",
            "platform": "ios",
            "environment": "dev",
            "capabilities": {"supports_live_activities": True},
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["token"] == "device-token-123"
    assert payload["platform"] == "ios"
    assert payload["environment"] == "dev"
    assert payload["capabilities"] == {"supports_live_activities": True}
    assert payload["isForeground"] is False
    assert payload["lastSeenAt"] is None

    disable = test_client.request(
        "DELETE",
        "/api/v1/device-tokens",
        headers=_auth_headers(),
        json={"token": "device-token-123"},
    )
    assert disable.status_code == 200
    disabled_payload = disable.json()
    assert disabled_payload["disabled"] is True


def test_device_tokens_presence_update(test_client):
    register = test_client.post(
        "/api/v1/device-tokens",
        headers=_auth_headers(),
        json={
            "token": "device-token-123",
            "platform": "ios",
            "environment": "dev",
            "capabilities": {"supports_live_activities": True},
        },
    )
    assert register.status_code == 200

    response = test_client.post(
        "/api/v1/device-tokens/presence",
        headers=_auth_headers(),
        json={
            "token": "device-token-123",
            "is_foreground": True,
            "last_seen_at": "2026-04-10T09:30:00Z",
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["token"] == "device-token-123"
    assert payload["isForeground"] is True
    assert payload["lastSeenAt"] == "2026-04-10T09:30:00+00:00"
    assert payload["capabilities"] == {"supports_live_activities": True}
