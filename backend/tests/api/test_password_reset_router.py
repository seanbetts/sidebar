def test_password_reset_request_accepts_email_without_auth(test_client, monkeypatch):
    observed_emails: list[str] = []

    async def fake_request(email: str) -> None:
        observed_emails.append(email)

    monkeypatch.setattr(
        "api.routers.auth.PasswordResetService.request_password_reset",
        fake_request,
    )

    response = test_client.post(
        "/api/v1/auth/password-reset/request",
        json={"email": "  person@example.com  "},
    )

    assert response.status_code == 202
    assert response.json() == {"status": "accepted"}
    assert observed_emails == ["person@example.com"]


def test_password_reset_request_is_not_blocked_by_invalid_auth_header(
    test_client, monkeypatch
):
    observed_emails: list[str] = []

    async def fake_request(email: str) -> None:
        observed_emails.append(email)

    monkeypatch.setattr(
        "api.routers.auth.PasswordResetService.request_password_reset",
        fake_request,
    )

    response = test_client.post(
        "/api/v1/auth/password-reset/request",
        headers={"Authorization": "Bearer definitely-not-a-real-token"},
        json={"email": "person@example.com"},
    )

    assert response.status_code == 202
    assert response.json() == {"status": "accepted"}
    assert observed_emails == ["person@example.com"]


def test_password_reset_request_requires_email_payload(test_client):
    response = test_client.post(
        "/api/v1/auth/password-reset/request",
        json={},
    )

    assert response.status_code == 422
