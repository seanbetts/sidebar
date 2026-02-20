"""Tests for backend/scripts/check_test_db_connectivity.py."""

from __future__ import annotations

from unittest.mock import MagicMock

from scripts.check_test_db_connectivity import (
    HOSTED_MIGRATE_CMD,
    LOCAL_SETUP_CMD,
    MigrationBaselineState,
    _collect_migration_baseline_state,
    _validate_migration_baseline,
)


def _mock_connection(
    *,
    alembic_exists: bool,
    public_table_count: int,
    alembic_row_count: int,
) -> MagicMock:
    connection = MagicMock()

    execute_results: list[MagicMock] = []
    for value in (alembic_exists, public_table_count):
        result = MagicMock()
        result.scalar_one.return_value = value
        execute_results.append(result)

    if alembic_exists:
        alembic_result = MagicMock()
        alembic_result.scalar_one.return_value = alembic_row_count
        execute_results.append(alembic_result)

    connection.execute.side_effect = execute_results
    return connection


def test_collect_migration_baseline_state_with_alembic_table() -> None:
    connection = _mock_connection(
        alembic_exists=True,
        public_table_count=6,
        alembic_row_count=1,
    )

    state = _collect_migration_baseline_state(connection)

    assert state == MigrationBaselineState(
        non_alembic_table_count=5,
        alembic_version_row_count=1,
    )


def test_collect_migration_baseline_state_without_alembic_table() -> None:
    connection = _mock_connection(
        alembic_exists=False,
        public_table_count=4,
        alembic_row_count=0,
    )

    state = _collect_migration_baseline_state(connection)

    assert state == MigrationBaselineState(
        non_alembic_table_count=4,
        alembic_version_row_count=0,
    )


def test_validate_migration_baseline_rejects_empty_unstamped_db() -> None:
    message = _validate_migration_baseline(
        MigrationBaselineState(non_alembic_table_count=0, alembic_version_row_count=0),
        hosted_lane=False,
    )

    assert message is not None
    assert LOCAL_SETUP_CMD in message


def test_validate_migration_baseline_rejects_unstamped_populated_schema() -> None:
    message = _validate_migration_baseline(
        MigrationBaselineState(non_alembic_table_count=3, alembic_version_row_count=0),
        hosted_lane=False,
    )

    assert message is not None
    assert "schema tables exist" in message
    assert LOCAL_SETUP_CMD in message


def test_validate_migration_baseline_rejects_stamped_schema_without_tables() -> None:
    message = _validate_migration_baseline(
        MigrationBaselineState(non_alembic_table_count=0, alembic_version_row_count=1),
        hosted_lane=False,
    )

    assert message is not None
    assert "application tables are missing" in message
    assert LOCAL_SETUP_CMD in message


def test_validate_migration_baseline_uses_hosted_command_when_needed() -> None:
    message = _validate_migration_baseline(
        MigrationBaselineState(non_alembic_table_count=0, alembic_version_row_count=2),
        hosted_lane=True,
    )

    assert message is not None
    assert HOSTED_MIGRATE_CMD in message


def test_validate_migration_baseline_accepts_healthy_state() -> None:
    message = _validate_migration_baseline(
        MigrationBaselineState(non_alembic_table_count=9, alembic_version_row_count=1),
        hosted_lane=False,
    )

    assert message is None
