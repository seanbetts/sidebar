"""Add user_id to notes and websites with backfill."""

from alembic import op
import sqlalchemy as sa


revision = "011_add_notes_websites_user_id"
down_revision = "010"
branch_labels = None
depends_on = None


BACKFILL_USER_ID = "81326b53-b7eb-42e2-b645-0c03cb5d5dd4"


def upgrade() -> None:
    """Add user_id columns, backfill, and update indexes."""
    op.add_column("notes", sa.Column("user_id", sa.Text(), nullable=True))
    op.add_column("websites", sa.Column("user_id", sa.Text(), nullable=True))

    op.execute(
        sa.text("UPDATE notes SET user_id = :user_id WHERE user_id IS NULL").bindparams(
            user_id=BACKFILL_USER_ID
        )
    )
    op.execute(
        sa.text("UPDATE websites SET user_id = :user_id WHERE user_id IS NULL").bindparams(
            user_id=BACKFILL_USER_ID
        )
    )

    op.alter_column("notes", "user_id", nullable=False)
    op.alter_column("websites", "user_id", nullable=False)

    op.create_index("idx_notes_user_id", "notes", ["user_id"])
    op.create_index("idx_websites_user_id", "websites", ["user_id"])

    op.drop_constraint("websites_url_key", "websites", type_="unique")
    op.create_unique_constraint("uq_websites_user_id_url", "websites", ["user_id", "url"])


def downgrade() -> None:
    """Drop user_id columns and restore indexes."""
    op.drop_constraint("uq_websites_user_id_url", "websites", type_="unique")
    op.create_unique_constraint("websites_url_key", "websites", ["url"])

    op.drop_index("idx_websites_user_id", table_name="websites")
    op.drop_index("idx_notes_user_id", table_name="notes")

    op.drop_column("websites", "user_id")
    op.drop_column("notes", "user_id")
