"""Configuration settings for Agent Smith Skills API."""
import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pathlib import Path


class Settings(BaseSettings):
    """Application settings with environment variable support."""

    # Base directories
    workspace_base: Path = Path("/workspace")
    skills_dir: Path = Path("/skills")

    # Authentication
    bearer_token: str

    # Database
    database_url: str = "postgresql://agent_smith:agent_smith_dev@postgres:5432/agent_smith"

    # Claude API configuration
    anthropic_api_key: str  # Loaded from Doppler or environment
    model_name: str = "claude-sonnet-4-5-20250929"

    # Write allowlist - only these paths can be written
    writable_paths: list[str] = ["/workspace/notes", "/workspace/documents"]

    # Resource limits
    skill_timeout_seconds: int = 30
    skill_max_output_bytes: int = 10 * 1024 * 1024  # 10MB
    skill_max_concurrent: int = 5

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


# Singleton settings instance
# In production: loads from environment or Doppler
# In tests: loads from .env.test when TESTING=1 is set
settings = Settings()
