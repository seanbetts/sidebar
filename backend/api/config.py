"""Configuration settings for sideBar Skills API."""
import os
from pathlib import Path
from urllib.parse import quote_plus, urlparse, urlunparse

from pydantic_settings import BaseSettings, SettingsConfigDict


def _build_database_url() -> str:
    """Build database URL from environment configuration.

    Returns:
        Database URL string suitable for SQLAlchemy.
    """
    explicit_url = os.getenv("DATABASE_URL")
    app_env = os.getenv("APP_ENV", "").lower()
    if explicit_url:
        if app_env not in {"prod", "production"}:
            parsed = urlparse(explicit_url)
            if parsed.hostname and "pooler.supabase.com" in parsed.hostname:
                port = parsed.port or 5432
                if port == 5432:
                    netloc = parsed.netloc
                    if "@" in netloc:
                        auth, hostport = netloc.split("@", 1)
                        host = hostport.split(":")[0]
                        netloc = f"{auth}@{host}:6543"
                    else:
                        host = netloc.split(":")[0]
                        netloc = f"{host}:6543"
                    return urlunparse(parsed._replace(netloc=netloc))
        return explicit_url

    supabase_password = os.getenv("SUPABASE_POSTGRES_PSWD")
    project_id = os.getenv("SUPABASE_PROJECT_ID")
    if not supabase_password or not project_id:
        return "postgresql://sidebar:sidebar_dev@postgres:5432/sidebar"

    db_name = os.getenv("SUPABASE_DB_NAME", "postgres")
    port = os.getenv("SUPABASE_DB_PORT", "5432")
    sslmode = os.getenv("SUPABASE_SSLMODE", "require")
    use_pooler = os.getenv("SUPABASE_USE_POOLER", "true").lower() in {"1", "true", "yes", "on"}
    pooler_mode = os.getenv("SUPABASE_POOLER_MODE", "transaction").lower()
    if use_pooler and app_env not in {"prod", "production"}:
        pooler_mode = "transaction"

    host = None
    user = None
    if use_pooler:
        host = os.getenv("SUPABASE_POOLER_HOST")
        if host:
            user = os.getenv("SUPABASE_POOLER_USER", f"postgres.{project_id}")
            if user == "sidebar_app" or user.startswith("sidebar_app."):
                supabase_password = os.getenv("SUPABASE_APP_PSWD", supabase_password)
            if pooler_mode == "transaction":
                # Transaction pooler uses 6543 regardless of session port config.
                port = "6543"
            else:
                port = os.getenv("SUPABASE_POOLER_PORT", "5432")
        else:
            use_pooler = False

    if not use_pooler:
        host = f"db.{project_id}.supabase.co"
        user = os.getenv("SUPABASE_DB_USER", "postgres")

    password = quote_plus(supabase_password)
    return f"postgresql://{user}:{password}@{host}:{port}/{db_name}?sslmode={sslmode}"


class Settings(BaseSettings):
    """Application settings with environment variable support."""

    # Base directories
    workspace_base: Path = Path(os.getenv("WORKSPACE_BASE", "/tmp/skills"))
    skills_dir: Path = Path(os.getenv("SKILLS_DIR", "/skills"))

    # Environment
    app_env: str = os.getenv("APP_ENV", "")
    disable_ssl_verify: bool = False
    custom_ca_bundle: str | None = None

    # Authentication
    bearer_token: str | None = None
    auth_dev_mode: bool = False
    default_user_id: str = "81326b53-b7eb-42e2-b645-0c03cb5d5dd4"

    # Supabase Auth
    supabase_url: str = ""
    supabase_anon_key: str = ""
    supabase_service_role_key: str | None = None

    # JWT validation
    jwt_audience: str = "authenticated"
    jwt_algorithm: str = "ES256"
    jwt_algorithms: list[str] = ["ES256", "HS256", "RS256"]
    supabase_jwt_secret: str | None = None
    jwks_cache_ttl_seconds: int = 3600
    jwt_issuer: str = ""

    # Database
    database_url: str = _build_database_url()
    db_pool_size: int = int(os.getenv("DB_POOL_SIZE", "15"))
    db_max_overflow: int = int(os.getenv("DB_MAX_OVERFLOW", "5"))

    # Claude API configuration
    anthropic_api_key: str  # Loaded from Doppler or environment
    model_name: str = "claude-sonnet-4-5-20250929"

    # Jina reader API
    jina_api_key: str = ""

    # Google Places API
    google_places_api_key: str | None = None

    # Write allowlist - only these paths can be written
    writable_paths: list[str] = [
        str(Path(os.getenv("WORKSPACE_BASE", "/tmp/skills")) / "notes"),
        str(Path(os.getenv("WORKSPACE_BASE", "/tmp/skills")) / "documents"),
    ]

    # Resource limits
    skill_timeout_seconds: int = 30
    skill_max_output_bytes: int = 10 * 1024 * 1024  # 10MB
    skill_max_concurrent: int = 5

    # Storage
    storage_backend: str = "local"  # local or r2
    r2_endpoint: str = ""
    r2_bucket: str = ""
    r2_access_key_id: str = ""
    r2_access_key: str = ""
    r2_secret_access_key: str = ""

    # Things bridge
    things_bridge_stale_seconds: int = int(os.getenv("THINGS_BRIDGE_STALE_SECONDS", "120"))
    things_bridge_timeout_seconds: int = int(os.getenv("THINGS_BRIDGE_TIMEOUT_SECONDS", "10"))
    things_bridge_backend_url: str = os.getenv("THINGS_BRIDGE_BACKEND_URL", "http://localhost:8001")
    things_bridge_device_id: str | None = os.getenv("THINGS_BRIDGE_DEVICE_ID") or None

    # Future JWT config (Phase 2)
    # jwt_secret: str = None
    # jwt_algorithm: str = "HS256"
    # jwt_expiry_hours: int = 24

    model_config = SettingsConfigDict(
        env_prefix="",
        case_sensitive=False,
        env_file=".env.test" if os.getenv("TESTING") else ".env",
        env_file_encoding="utf-8",
        extra="ignore"  # Ignore extra environment variables (like DOPPLER_TOKEN)
    )

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        if self.app_env in {"prod", "production"} and self.disable_ssl_verify:
            raise ValueError(
                "SSL verification cannot be disabled in production. "
                "Set APP_ENV=local/dev or provide CUSTOM_CA_BUNDLE."
            )

    @property
    def allow_auth_dev_mode(self) -> bool:
        """Return True if AUTH_DEV_MODE is allowed in this environment."""
        if not self.auth_dev_mode:
            return True
        if os.getenv("TESTING"):
            return True
        return self.app_env in {"local", "test"}


# Singleton settings instance
# In production: loads from environment or Doppler
# In tests: loads from .env.test when TESTING=1 is set
settings = Settings()
