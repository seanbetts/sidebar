"""Fix multiple permissive policies by splitting FOR ALL into separate operations.

The issue: We created both `_select_optimized` (FOR SELECT) and `_backend_operations` (FOR ALL).
Since FOR ALL includes SELECT, this creates duplicate SELECT policies.

The fix: Replace FOR ALL with separate FOR INSERT, FOR UPDATE, FOR DELETE policies.

Revision ID: 032_fix_multiple_policies
Revises: 031_optimize_rls_policies
Create Date: 2026-01-07 16:30:00
"""

from alembic import op

revision = "032_fix_multiple_policies"
down_revision = "031_optimize_rls_policies"
branch_labels = None
depends_on = None


# Tables with consolidated SELECT policy
TABLES_WITH_DUAL_POLICIES = [
    "notes",
    "websites",
    "ingested_files",
    "file_processing_jobs",
]


def upgrade() -> None:
    """Replace FOR ALL policies with separate INSERT/UPDATE/DELETE policies."""

    for table in TABLES_WITH_DUAL_POLICIES:
        # Drop the FOR ALL policy
        op.execute(f"DROP POLICY IF EXISTS {table}_backend_operations ON {table}")

        # Create separate policies for INSERT, UPDATE, DELETE
        if table == "file_processing_jobs":
            # Special case: uses file_id JOIN
            # INSERT: only WITH CHECK
            op.execute(f"""
                CREATE POLICY {table}_backend_insert
                ON {table}
                FOR INSERT
                WITH CHECK (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
            """)
            # UPDATE: both USING and WITH CHECK
            op.execute(f"""
                CREATE POLICY {table}_backend_update
                ON {table}
                FOR UPDATE
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
                WITH CHECK (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
            """)
            # DELETE: only USING
            op.execute(f"""
                CREATE POLICY {table}_backend_delete
                ON {table}
                FOR DELETE
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
            """)
        else:
            # Normal tables: notes, websites, ingested_files
            # INSERT: only WITH CHECK
            op.execute(f"""
                CREATE POLICY {table}_backend_insert
                ON {table}
                FOR INSERT
                WITH CHECK (user_id = (select current_setting('app.user_id', true)))
            """)
            # UPDATE: both USING and WITH CHECK
            op.execute(f"""
                CREATE POLICY {table}_backend_update
                ON {table}
                FOR UPDATE
                USING (user_id = (select current_setting('app.user_id', true)))
                WITH CHECK (user_id = (select current_setting('app.user_id', true)))
            """)
            # DELETE: only USING
            op.execute(f"""
                CREATE POLICY {table}_backend_delete
                ON {table}
                FOR DELETE
                USING (user_id = (select current_setting('app.user_id', true)))
            """)


def downgrade() -> None:
    """Revert to FOR ALL policy."""

    for table in TABLES_WITH_DUAL_POLICIES:
        # Drop separate operation policies
        for operation in ["insert", "update", "delete"]:
            op.execute(f"DROP POLICY IF EXISTS {table}_backend_{operation} ON {table}")

        # Recreate FOR ALL policy
        if table == "file_processing_jobs":
            op.execute(f"""
                CREATE POLICY {table}_backend_operations
                ON {table}
                FOR ALL
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
                WITH CHECK (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (select current_setting('app.user_id', true))
                    )
                )
            """)
        else:
            op.execute(f"""
                CREATE POLICY {table}_backend_operations
                ON {table}
                FOR ALL
                USING (user_id = (select current_setting('app.user_id', true)))
                WITH CHECK (user_id = (select current_setting('app.user_id', true)))
            """)
