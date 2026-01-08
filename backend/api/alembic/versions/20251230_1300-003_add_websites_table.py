"""Add websites table for archived web content

Revision ID: 003
Revises: 002
Create Date: 2025-12-30 13:00:00.000000

"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '003'
down_revision: str | None = '002'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Create websites table with metadata."""
    op.create_table(
        'websites',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('url', sa.Text(), nullable=False, unique=True),
        sa.Column('url_full', sa.Text(), nullable=True),
        sa.Column('domain', sa.Text(), nullable=False),
        sa.Column('title', sa.Text(), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('source', sa.Text(), nullable=True),
        sa.Column('saved_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('published_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('metadata', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_opened_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )

    op.create_index('idx_websites_domain', 'websites', ['domain'])
    op.create_index('idx_websites_saved_at', 'websites', ['saved_at'])
    op.create_index('idx_websites_updated_at', 'websites', ['updated_at'])
    op.create_index('idx_websites_last_opened_at', 'websites', ['last_opened_at'])
    op.create_index('idx_websites_metadata_pinned', 'websites', [sa.text("(metadata->>'pinned')")])


def downgrade() -> None:
    """Drop websites table."""
    op.drop_index('idx_websites_metadata_pinned', table_name='websites')
    op.drop_index('idx_websites_last_opened_at', table_name='websites')
    op.drop_index('idx_websites_updated_at', table_name='websites')
    op.drop_index('idx_websites_saved_at', table_name='websites')
    op.drop_index('idx_websites_domain', table_name='websites')
    op.drop_table('websites')
