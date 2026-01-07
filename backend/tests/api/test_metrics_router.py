from api.config import settings


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


def test_web_vitals_requires_auth(test_client):
    response = test_client.post(
        "/api/v1/metrics/web-vitals",
        json={"name": "LCP", "value": 1200, "rating": "good"},
    )
    assert response.status_code == 401


def test_web_vitals_accepts_valid_payload(test_client):
    response = test_client.post(
        "/api/v1/metrics/web-vitals",
        headers=_auth_headers(),
        json={"name": "LCP", "value": 1200, "rating": "good"},
    )
    assert response.status_code == 204


def test_web_vitals_rejects_invalid_name(test_client):
    response = test_client.post(
        "/api/v1/metrics/web-vitals",
        headers=_auth_headers(),
        json={"name": "BAD", "value": 1200, "rating": "good"},
    )
    assert response.status_code == 400


def test_chat_metrics_requires_auth(test_client):
    response = test_client.post(
        "/api/v1/metrics/chat",
        json={"name": "stream_duration_ms", "value": 1200},
    )
    assert response.status_code == 401


def test_chat_metrics_accepts_valid_payload(test_client):
    response = test_client.post(
        "/api/v1/metrics/chat",
        headers=_auth_headers(),
        json={"name": "stream_duration_ms", "value": 1200},
    )
    assert response.status_code == 204


def test_chat_metrics_rejects_invalid_name(test_client):
    response = test_client.post(
        "/api/v1/metrics/chat",
        headers=_auth_headers(),
        json={"name": "bad_metric", "value": 1200},
    )
    assert response.status_code == 400
