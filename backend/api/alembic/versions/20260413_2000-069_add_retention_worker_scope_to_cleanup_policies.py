"""Allow retention worker to clean up rows across users.

Revision ID: 069_add_retention_worker_scope_to_cleanup_policies
Revises: 068_add_retention_tracking_and_cleanup_indexes
Create Date: 2026-04-13 20:00:00
"""

from __future__ import annotations

from alembic import op

revision = "069_add_retention_worker_scope_to_cleanup_policies"
down_revision = "068_add_retention_tracking_and_cleanup_indexes"
branch_labels = None
depends_on = None

APP_USER = "(SELECT current_setting('app.user_id', true))"
AUTH_UID = "(SELECT auth.uid()::text)"
INGESTION_SCOPE = "(SELECT current_setting('app.ingestion_scope', true)) = 'all'"
RETENTION_SCOPE = "(SELECT current_setting('app.retention_worker_scope', true)) = 'all'"
WEBSITE_SCOPE = "current_setting('app.website_worker_scope', true) = 'all'"

SIMPLE_SELECT_TABLES = ("notes", "websites")
TASK_TABLES = ("task_groups", "task_projects", "tasks", "task_operation_log")


def _recreate_simple_table_policies(table: str, *, include_retention: bool) -> None:
    op.execute(f"DROP POLICY IF EXISTS {table}_backend_delete ON {table}")
    op.execute(f"DROP POLICY IF EXISTS {table}_backend_insert ON {table}")
    op.execute(f"DROP POLICY IF EXISTS {table}_backend_update ON {table}")
    op.execute(f"DROP POLICY IF EXISTS {table}_select_optimized ON {table}")

    user_or_retention = f"user_id = {APP_USER}"
    if include_retention:
        user_or_retention = f"({user_or_retention} OR {RETENTION_SCOPE})"

    select_predicate = f"user_id = {APP_USER} OR user_id = {AUTH_UID}"
    if include_retention:
        select_predicate = f"({select_predicate} OR {RETENTION_SCOPE})"

    op.execute(
        f"""
        CREATE POLICY {table}_backend_insert
        ON {table}
        FOR INSERT
        WITH CHECK (user_id = {APP_USER})
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_backend_update
        ON {table}
        FOR UPDATE
        USING ({user_or_retention})
        WITH CHECK ({user_or_retention})
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_backend_delete
        ON {table}
        FOR DELETE
        USING ({user_or_retention})
        """
    )
    op.execute(
        f"""
        CREATE POLICY {table}_select_optimized
        ON {table}
        FOR SELECT
        USING ({select_predicate})
        """
    )


def _recreate_ingested_file_policies(*, include_retention: bool) -> None:
    op.execute("DROP POLICY IF EXISTS ingested_files_backend_delete ON ingested_files")
    op.execute("DROP POLICY IF EXISTS ingested_files_backend_insert ON ingested_files")
    op.execute("DROP POLICY IF EXISTS ingested_files_backend_update ON ingested_files")
    op.execute(
        "DROP POLICY IF EXISTS ingested_files_select_optimized ON ingested_files"
    )

    update_delete_predicate = f"user_id = {APP_USER}"
    if include_retention:
        update_delete_predicate = f"({update_delete_predicate} OR {RETENTION_SCOPE})"

    select_predicate = (
        f"user_id = {APP_USER} OR user_id = {AUTH_UID} OR {INGESTION_SCOPE}"
    )
    if include_retention:
        select_predicate = f"({select_predicate} OR {RETENTION_SCOPE})"

    op.execute(
        f"""
        CREATE POLICY ingested_files_backend_insert
        ON ingested_files
        FOR INSERT
        WITH CHECK (user_id = {APP_USER})
        """
    )
    op.execute(
        f"""
        CREATE POLICY ingested_files_backend_update
        ON ingested_files
        FOR UPDATE
        USING ({update_delete_predicate})
        WITH CHECK ({update_delete_predicate})
        """
    )
    op.execute(
        f"""
        CREATE POLICY ingested_files_backend_delete
        ON ingested_files
        FOR DELETE
        USING ({update_delete_predicate})
        """
    )
    op.execute(
        f"""
        CREATE POLICY ingested_files_select_optimized
        ON ingested_files
        FOR SELECT
        USING ({select_predicate})
        """
    )


def _recreate_file_derivative_policies(*, include_retention: bool) -> None:
    op.execute(
        "DROP POLICY IF EXISTS file_derivatives_user_isolation ON file_derivatives"
    )

    predicate = (
        f"file_id IN (SELECT id FROM ingested_files WHERE user_id = {APP_USER})"
    )
    if include_retention:
        predicate = f"({predicate} OR {RETENTION_SCOPE})"

    op.execute(
        f"""
        CREATE POLICY file_derivatives_user_isolation
        ON file_derivatives
        USING ({predicate})
        WITH CHECK ({predicate})
        """
    )


def _recreate_file_processing_job_policies(*, include_retention: bool) -> None:
    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_backend_delete ON file_processing_jobs"
    )
    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_backend_insert ON file_processing_jobs"
    )
    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_backend_update ON file_processing_jobs"
    )
    op.execute(
        "DROP POLICY IF EXISTS file_processing_jobs_select_optimized ON file_processing_jobs"
    )

    owned_file_predicate = (
        f"file_id IN (SELECT id FROM ingested_files WHERE user_id = {APP_USER})"
    )
    update_delete_predicate = owned_file_predicate
    if include_retention:
        update_delete_predicate = f"({update_delete_predicate} OR {RETENTION_SCOPE})"

    select_predicate = (
        "file_id IN ("
        "SELECT id FROM ingested_files "
        f"WHERE user_id = {APP_USER} OR user_id = {AUTH_UID}"
        f") OR {INGESTION_SCOPE}"
    )
    if include_retention:
        select_predicate = f"({select_predicate} OR {RETENTION_SCOPE})"

    update_predicate = f"({owned_file_predicate} OR {INGESTION_SCOPE})"
    if include_retention:
        update_predicate = f"({update_predicate} OR {RETENTION_SCOPE})"

    op.execute(
        f"""
        CREATE POLICY file_processing_jobs_backend_insert
        ON file_processing_jobs
        FOR INSERT
        WITH CHECK ({owned_file_predicate})
        """
    )
    op.execute(
        f"""
        CREATE POLICY file_processing_jobs_backend_update
        ON file_processing_jobs
        FOR UPDATE
        USING ({update_predicate})
        WITH CHECK ({update_predicate})
        """
    )
    op.execute(
        f"""
        CREATE POLICY file_processing_jobs_backend_delete
        ON file_processing_jobs
        FOR DELETE
        USING ({update_delete_predicate})
        """
    )
    op.execute(
        f"""
        CREATE POLICY file_processing_jobs_select_optimized
        ON file_processing_jobs
        FOR SELECT
        USING ({select_predicate})
        """
    )


def _recreate_task_policies(*, include_retention: bool) -> None:
    for table in TASK_TABLES:
        op.execute(f"DROP POLICY IF EXISTS {table}_user_isolation ON {table}")
        predicate = f"user_id = current_setting('app.user_id', true)"
        if include_retention:
            predicate = f"({predicate} OR {RETENTION_SCOPE})"
        op.execute(
            f"""
            CREATE POLICY {table}_user_isolation
            ON {table}
            USING ({predicate})
            WITH CHECK ({predicate})
            """
        )


def _recreate_provider_key_policy(*, include_retention: bool) -> None:
    op.execute(
        "DROP POLICY IF EXISTS user_ai_provider_keys_user_isolation "
        "ON user_ai_provider_keys"
    )
    predicate = f"user_id = {APP_USER} OR user_id = {AUTH_UID}"
    if include_retention:
        predicate = f"({predicate} OR {RETENTION_SCOPE})"
    op.execute(
        f"""
        CREATE POLICY user_ai_provider_keys_user_isolation
        ON user_ai_provider_keys
        USING ({predicate})
        WITH CHECK ({predicate})
        """
    )


def _recreate_website_job_policy(*, include_retention: bool) -> None:
    op.execute(
        "DROP POLICY IF EXISTS website_processing_jobs_worker_scope "
        "ON website_processing_jobs"
    )
    predicate = (
        f"user_id = current_setting('app.user_id', true) OR {WEBSITE_SCOPE}"
    )
    if include_retention:
        predicate = f"({predicate} OR {RETENTION_SCOPE})"
    op.execute(
        f"""
        CREATE POLICY website_processing_jobs_worker_scope
        ON website_processing_jobs
        USING ({predicate})
        WITH CHECK ({predicate})
        """
    )


def upgrade() -> None:
    """Add retention-worker scope to cleanup-managed table policies."""
    for table in SIMPLE_SELECT_TABLES:
        _recreate_simple_table_policies(table, include_retention=True)
    _recreate_ingested_file_policies(include_retention=True)
    _recreate_file_derivative_policies(include_retention=True)
    _recreate_file_processing_job_policies(include_retention=True)
    _recreate_task_policies(include_retention=True)
    _recreate_provider_key_policy(include_retention=True)
    _recreate_website_job_policy(include_retention=True)


def downgrade() -> None:
    """Remove retention-worker scope from cleanup-managed table policies."""
    for table in SIMPLE_SELECT_TABLES:
        _recreate_simple_table_policies(table, include_retention=False)
    _recreate_ingested_file_policies(include_retention=False)
    _recreate_file_derivative_policies(include_retention=False)
    _recreate_file_processing_job_policies(include_retention=False)
    _recreate_task_policies(include_retention=False)
    _recreate_provider_key_policy(include_retention=False)
    _recreate_website_job_policy(include_retention=False)
