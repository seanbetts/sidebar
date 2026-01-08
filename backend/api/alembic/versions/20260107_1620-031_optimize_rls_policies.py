"""Optimize RLS policies for performance.

Fixes two issues:
1. Wraps auth function calls in subqueries to prevent per-row re-evaluation
2. Consolidates duplicate SELECT policies into single optimized policies

Revision ID: 031_optimize_rls_policies
Revises: 030_repair_missing_rls
Create Date: 2026-01-07 16:20:00
"""

from alembic import op

revision = "031_optimize_rls_policies"
down_revision = "030_repair_missing_rls"
branch_labels = None
depends_on = None


# Tables with both user_isolation and realtime_select policies
TABLES_WITH_DUAL_POLICIES = [
    "notes",
    "websites",
    "ingested_files",
    "file_processing_jobs",
]

# Tables with only user_isolation policy (direct user_id column)
TABLES_WITH_USER_ISOLATION_ONLY = [
    "conversations",
    "user_settings",
    "user_memories",
    "files",
    "website_processing_jobs",
    "things_bridges",
]

# Tables that use file_id -> ingested_files.user_id relationship
TABLES_WITH_FILE_ID_ISOLATION = [
    "file_derivatives",
]

# things_bridge_install_tokens has 4 separate policies using auth.uid()
THINGS_BRIDGE_POLICIES = [
    "things_bridge_install_tokens_select",
    "things_bridge_install_tokens_insert",
    "things_bridge_install_tokens_update",
    "things_bridge_install_tokens_delete",
]


def upgrade() -> None:
    """Optimize RLS policies for better performance."""
    # 1. Fix tables with both policies - consolidate into single optimized policy
    for table in TABLES_WITH_DUAL_POLICIES:
        # Drop old policies
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        op.execute(f"DROP POLICY IF EXISTS {table}_realtime_select ON {table}")

        # Create single optimized policy that works for both backend and realtime
        if table == "file_processing_jobs":
            # Special case: file_processing_jobs needs JOIN to ingested_files
            op.execute(f"""
                CREATE POLICY {table}_select_optimized
                ON {table}
                FOR SELECT
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (SELECT current_setting('app.user_id', true))
                           OR user_id = (SELECT auth.uid()::text)
                    )
                )
            """)
            # Keep ALL operations policy for backend
            op.execute(f"""
                CREATE POLICY {table}_backend_operations
                ON {table}
                FOR ALL
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (SELECT current_setting('app.user_id', true))
                    )
                )
                WITH CHECK (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = (SELECT current_setting('app.user_id', true))
                    )
                )
            """)
        else:
            # For notes, websites, ingested_files: single policy for SELECT
            op.execute(f"""
                CREATE POLICY {table}_select_optimized
                ON {table}
                FOR SELECT
                USING (
                    user_id = (SELECT current_setting('app.user_id', true))
                    OR user_id = (SELECT auth.uid()::text)
                )
            """)
            # Keep ALL operations policy for backend (INSERT/UPDATE/DELETE)
            op.execute(f"""
                CREATE POLICY {table}_backend_operations
                ON {table}
                FOR ALL
                USING (user_id = (SELECT current_setting('app.user_id', true)))
                WITH CHECK (user_id = (SELECT current_setting('app.user_id', true)))
            """)

    # 2. Fix tables with only user_isolation policy - just wrap in subquery
    for table in TABLES_WITH_USER_ISOLATION_ONLY:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        op.execute(f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING (user_id = (SELECT current_setting('app.user_id', true)))
            WITH CHECK (user_id = (SELECT current_setting('app.user_id', true)))
        """)

    # 2b. Fix tables that use file_id relationship - wrap in subquery
    for table in TABLES_WITH_FILE_ID_ISOLATION:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        op.execute(f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING (
                file_id IN (
                    SELECT id FROM ingested_files
                    WHERE user_id = (SELECT current_setting('app.user_id', true))
                )
            )
            WITH CHECK (
                file_id IN (
                    SELECT id FROM ingested_files
                    WHERE user_id = (SELECT current_setting('app.user_id', true))
                )
            )
        """)

    # 3. Fix things_bridge_install_tokens policies - wrap auth.uid() in subqueries
    for policy in THINGS_BRIDGE_POLICIES:
        action = policy.split('_')[-1].upper()
        op.execute(f"DROP POLICY IF EXISTS {policy} ON things_bridge_install_tokens")

        if action == "SELECT":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR SELECT
                USING (user_id = (SELECT auth.uid()::text))
            """)
        elif action == "INSERT":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR INSERT
                WITH CHECK (user_id = (SELECT auth.uid()::text))
            """)
        elif action == "UPDATE":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR UPDATE
                USING (user_id = (SELECT auth.uid()::text))
                WITH CHECK (user_id = (SELECT auth.uid()::text))
            """)
        elif action == "DELETE":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR DELETE
                USING (user_id = (SELECT auth.uid()::text))
            """)


def downgrade() -> None:
    """Revert to original policies."""
    # Revert dual policy tables
    for table in TABLES_WITH_DUAL_POLICIES:
        op.execute(f"DROP POLICY IF EXISTS {table}_select_optimized ON {table}")
        op.execute(f"DROP POLICY IF EXISTS {table}_backend_operations ON {table}")

        # Recreate original policies
        op.execute(f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING (user_id = current_setting('app.user_id', true))
            WITH CHECK (user_id = current_setting('app.user_id', true))
        """)

        if table != "file_processing_jobs":
            op.execute(f"""
                CREATE POLICY {table}_realtime_select
                ON {table}
                FOR SELECT
                USING (user_id = auth.uid()::text)
            """)
        else:
            op.execute("""
                CREATE POLICY file_processing_jobs_realtime_select
                ON file_processing_jobs
                FOR SELECT
                USING (
                    file_id IN (
                        SELECT id FROM ingested_files
                        WHERE user_id = auth.uid()::text
                    )
                )
            """)

    # Revert user_isolation only tables
    for table in TABLES_WITH_USER_ISOLATION_ONLY:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        op.execute(f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING (user_id = current_setting('app.user_id', true))
            WITH CHECK (user_id = current_setting('app.user_id', true))
        """)

    # Revert file_id relationship tables
    for table in TABLES_WITH_FILE_ID_ISOLATION:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        op.execute(f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING (
                file_id IN (
                    SELECT id FROM ingested_files
                    WHERE user_id = current_setting('app.user_id', true)
                )
            )
            WITH CHECK (
                file_id IN (
                    SELECT id FROM ingested_files
                    WHERE user_id = current_setting('app.user_id', true)
                )
            )
        """)

    # Revert things_bridge_install_tokens policies
    for policy in THINGS_BRIDGE_POLICIES:
        action = policy.split('_')[-1].upper()
        op.execute(f"DROP POLICY IF EXISTS {policy} ON things_bridge_install_tokens")

        if action == "SELECT":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR SELECT
                USING (user_id = auth.uid()::text)
            """)
        elif action == "INSERT":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR INSERT
                WITH CHECK (user_id = auth.uid()::text)
            """)
        elif action == "UPDATE":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR UPDATE
                USING (user_id = auth.uid()::text)
                WITH CHECK (user_id = auth.uid()::text)
            """)
        elif action == "DELETE":
            op.execute(f"""
                CREATE POLICY {policy}
                ON things_bridge_install_tokens
                FOR DELETE
                USING (user_id = auth.uid()::text)
            """)
