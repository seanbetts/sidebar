"""Add conversation-level assistant provider/model fields.

Revision ID: 049_add_conversation_ai_provider_model
Revises: 048_add_user_ai_provider_keys
Create Date: 2026-02-19 23:30:00.000000
"""

from collections.abc import Sequence

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "049_add_conversation_ai_provider_model"
down_revision: str | None = "048_add_user_ai_provider_keys"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add conversation AI provider/model columns."""
    op.execute("ALTER TABLE conversations " "ADD COLUMN IF NOT EXISTS ai_provider text")
    op.execute("ALTER TABLE conversations " "ADD COLUMN IF NOT EXISTS ai_model text")


def downgrade() -> None:
    """Remove conversation AI provider/model columns."""
    op.execute("ALTER TABLE conversations " "DROP COLUMN IF EXISTS ai_model")
    op.execute("ALTER TABLE conversations " "DROP COLUMN IF EXISTS ai_provider")
