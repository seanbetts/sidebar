"""Add notes table for markdown storage

Revision ID: 002
Revises: 001
Create Date: 2025-12-30 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '002'
down_revision: Union[str, None] = '001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create notes table with JSONB metadata."""
    op.create_table(
        'notes',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column('title', sa.Text(), nullable=False),
        sa.Column('content', sa.Text(), nullable=False),
        sa.Column('metadata', postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('last_opened_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    )

    op.create_index('idx_notes_updated_at', 'notes', ['updated_at'])
    op.create_index('idx_notes_last_opened_at', 'notes', ['last_opened_at'])
    op.create_index('idx_notes_metadata_folder', 'notes', [sa.text("(metadata->>'folder')")])
    op.create_index('idx_notes_metadata_pinned', 'notes', [sa.text("(metadata->>'pinned')")])


def downgrade() -> None:
    """Drop notes table."""
    op.drop_index('idx_notes_metadata_pinned', table_name='notes')
    op.drop_index('idx_notes_metadata_folder', table_name='notes')
    op.drop_index('idx_notes_last_opened_at', table_name='notes')
    op.drop_index('idx_notes_updated_at', table_name='notes')
    op.drop_table('notes')
