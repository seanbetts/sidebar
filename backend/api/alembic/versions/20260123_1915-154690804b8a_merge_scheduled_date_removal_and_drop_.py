"""Merge scheduled_date removal and drop task tags

Revision ID: 154690804b8a
Revises: 036_remove_scheduled_date, 037_drop_task_tags
Create Date: 2026-01-23 19:15:53.801253

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '154690804b8a'
down_revision: Union[str, None] = ('036_remove_scheduled_date', '037_drop_task_tags')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
