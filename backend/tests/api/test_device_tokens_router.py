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
        },
    )
    assert response.status_code == 200
    payload = response.json()
    assert payload["token"] == "device-token-123"
    assert payload["platform"] == "ios"
    assert payload["environment"] == "dev"

    disable = test_client.delete(
        "/api/v1/device-tokens",
        headers=_auth_headers(),
        json={"token": "device-token-123"},
    )
    assert disable.status_code == 200
    disabled_payload = disable.json()
    assert disabled_payload["disabled"] is True
