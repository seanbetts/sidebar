"""Add conversations table with JSONB messages

Revision ID: 001
Revises:
Create Date: 2025-12-21 17:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '001'
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create conversations table with JSONB message storage."""
    op.create_table(
        'conversations',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', sa.String(255), nullable=False, index=True),
        sa.Column('title', sa.String(500), nullable=False),
        sa.Column('title_generated', sa.Boolean(), default=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, index=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False, index=True),
        sa.Column('is_archived', sa.Boolean(), default=False),
        sa.Column('first_message', sa.Text()),
        sa.Column('message_count', sa.Integer(), default=0),
        sa.Column('messages', postgresql.JSONB(), nullable=False, server_default='[]'),
    )

    # Create GIN index on JSONB messages for fast searching
    op.create_index(
        'idx_conversations_messages_gin',
        'conversations',
        ['messages'],
        postgresql_using='gin'
    )


def downgrade() -> None:
    """Drop conversations table."""
    op.drop_index('idx_conversations_messages_gin', table_name='conversations')
    op.drop_table('conversations')
