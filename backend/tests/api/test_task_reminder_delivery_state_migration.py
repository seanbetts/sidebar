"""Tests for the durable task-reminder delivery-state migration."""

from __future__ import annotations

import importlib.util
from pathlib import Path
from unittest.mock import MagicMock


def _load_migration_module():
    migration_path = (
        Path(__file__).resolve().parents[2]
        / "api"
        / "alembic"
        / "versions"
        / "20260817_0900-078_add_task_reminder_delivery_states.py"
    )
    assert migration_path.exists()
    spec = importlib.util.spec_from_file_location(
        "migration_078_add_task_reminder_delivery_states",
        migration_path,
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_upgrade_creates_bounded_product_state_with_scoped_rls() -> None:
    migration = _load_migration_module()
    created_table: tuple[tuple[object, ...], dict[str, object]] | None = None
    executed_sql: list[str] = []

    class FakeOp:
        @staticmethod
        def create_table(*args, **kwargs) -> None:
            nonlocal created_table
            created_table = (args, kwargs)

        @staticmethod
        def execute(statement: str) -> None:
            executed_sql.append(statement)

    migration.op = FakeOp()

    migration.upgrade()

    assert created_table is not None
    args, _ = created_table
    assert args[0] == "task_reminder_delivery_states"
    elements = args[1:]
    columns = {element.name: element for element in elements if hasattr(element, "type")}
    assert set(columns) == {
        "id",
        "user_id",
        "schedule_timezone",
        "local_date",
        "accepted_delivery_keys",
        "completed_at",
        "created_at",
        "updated_at",
    }
    assert columns["accepted_delivery_keys"].nullable is False

    foreign_keys = [
        element for element in elements if element.__class__.__name__ == "ForeignKeyConstraint"
    ]
    assert len(foreign_keys) == 1
    assert foreign_keys[0].ondelete == "CASCADE"
    assert list(foreign_keys[0].elements)[0].target_fullname == "user_settings.user_id"

    unique_constraints = [
        element for element in elements if element.__class__.__name__ == "UniqueConstraint"
    ]
    assert len(unique_constraints) == 1
    assert unique_constraints[0]._pending_colargs == [
        "user_id",
        "schedule_timezone",
    ]

    assert (
        "ALTER TABLE task_reminder_delivery_states ENABLE ROW LEVEL SECURITY"
        in executed_sql
    )
    user_policy = _only_statement_containing(executed_sql, "_user_operations")
    assert "current_setting('app.user_id', true)" in user_policy
    assert "USING" in user_policy
    assert "WITH CHECK" in user_policy

    worker_policy = _only_statement_containing(executed_sql, "_worker_select")
    assert "FOR SELECT" in worker_policy
    assert "current_setting('app.notification_worker_scope', true)" in worker_policy
    assert "= 'all'" in worker_policy

    normalized_sql = " ".join(executed_sql)
    assert "auth.uid" not in normalized_sql
    assert "GRANT" not in normalized_sql
    assert "notification_diagnostics" not in normalized_sql


def test_downgrade_removes_state_table_and_policies() -> None:
    migration = _load_migration_module()
    executed_sql: list[str] = []
    fake_op = MagicMock()
    fake_op.execute.side_effect = executed_sql.append
    migration.op = fake_op

    migration.downgrade()

    assert any("_user_operations" in statement for statement in executed_sql)
    assert any("_worker_select" in statement for statement in executed_sql)
    fake_op.drop_table.assert_called_once_with("task_reminder_delivery_states")


def _only_statement_containing(statements: list[str], needle: str) -> str:
    matches = [statement for statement in statements if needle in statement]
    assert len(matches) == 1
    return matches[0]
