"""Set ai_fallback_to_managed default to false (strict mode).

Revision ID: 050_default_ai_fallback_strict
Revises: 049_add_conversation_ai_provider_model
Create Date: 2026-02-19 23:45:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "050_default_ai_fallback_strict"
down_revision: str | None = "049_add_conversation_ai_provider_model"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Change ai_fallback_to_managed column default to false."""
    op.execute(
        "ALTER TABLE user_settings "
        "ALTER COLUMN ai_fallback_to_managed SET DEFAULT false"
    )


def downgrade() -> None:
    """Restore ai_fallback_to_managed column default to true."""
    op.execute(
        "ALTER TABLE user_settings "
        "ALTER COLUMN ai_fallback_to_managed SET DEFAULT true"
    )
