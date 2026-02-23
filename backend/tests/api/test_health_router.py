"""Tests for health router configuration checks."""

from api.config import settings


def test_health_allows_explicit_database_url_without_pooler_env(
    test_client, monkeypatch
):
    monkeypatch.setattr(settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql://sidebar:secret@db.example.com:5432/postgres",
    )
    monkeypatch.delenv("SUPABASE_PROJECT_ID", raising=False)
    monkeypatch.delenv("SUPABASE_POSTGRES_PSWD", raising=False)
    monkeypatch.delenv("SUPABASE_APP_PSWD", raising=False)
    monkeypatch.delenv("SUPABASE_POOLER_HOST", raising=False)
    monkeypatch.delenv("SUPABASE_ANON_KEY", raising=False)

    response = test_client.get("/api/health")

    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_health_reports_missing_pooler_env_without_database_url(
    test_client, monkeypatch
):
    monkeypatch.setattr(settings, "supabase_url", "https://example.supabase.co")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    monkeypatch.delenv("DATABASE_URL_DIRECT", raising=False)
    monkeypatch.setenv("SUPABASE_USE_POOLER", "true")
    monkeypatch.delenv("SUPABASE_PROJECT_ID", raising=False)
    monkeypatch.delenv("SUPABASE_POSTGRES_PSWD", raising=False)
    monkeypatch.delenv("SUPABASE_APP_PSWD", raising=False)
    monkeypatch.delenv("SUPABASE_POOLER_HOST", raising=False)

    response = test_client.get("/api/health")

    assert response.status_code == 503
    payload = response.json()
    assert payload["status"] == "unhealthy"
    assert "SUPABASE_PROJECT_ID" in payload["missing"]
    assert "SUPABASE_POSTGRES_PSWD" in payload["missing"]
    assert "SUPABASE_POOLER_HOST" in payload["missing"]
