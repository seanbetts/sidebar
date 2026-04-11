from __future__ import annotations

from datetime import UTC, datetime
from sqlalchemy.exc import NoResultFound

from api.models.device_token import DeviceToken
from api.services import device_token_service
from api.services.device_token_service import DeviceTokenService


class _StaleDeviceTokenQueryProxy:
    def __init__(self, query, *, return_none_once: dict[str, bool]):
        self._query = query
        self._return_none_once = return_none_once

    def filter(self, *criteria):
        return _StaleDeviceTokenQueryProxy(
            self._query.filter(*criteria),
            return_none_once=self._return_none_once,
        )

    def one_or_none(self):
        if self._return_none_once["enabled"]:
            self._return_none_once["enabled"] = False
            return None
        return self._query.one_or_none()

    def __getattr__(self, name):
        return getattr(self._query, name)


class _DelayedVisibleDeviceTokenQueryProxy:
    def __init__(self, query, *, invisible_lookups_remaining: dict[str, int]):
        self._query = query
        self._invisible_lookups_remaining = invisible_lookups_remaining

    def filter(self, *criteria):
        return _DelayedVisibleDeviceTokenQueryProxy(
            self._query.filter(*criteria),
            invisible_lookups_remaining=self._invisible_lookups_remaining,
        )

    def one_or_none(self):
        if self._invisible_lookups_remaining["count"] > 0:
            self._invisible_lookups_remaining["count"] -= 1
            return None
        return self._query.one_or_none()

    def one(self):
        result = self.one_or_none()
        if result is None:
            raise NoResultFound()
        return result

    def __getattr__(self, name):
        return getattr(self._query, name)


def test_register_token_recovers_when_insert_loses_duplicate_token_race(
    test_db,
    monkeypatch,
):
    existing = DeviceToken(
        user_id="user-old",
        token="device-token-123",
        platform="ios",
        environment="dev",
        capabilities={"supports_live_activities": False},
        is_foreground=False,
        last_seen_at=None,
        disabled_at=datetime(2026, 4, 10, 17, 44, tzinfo=UTC),
    )
    test_db.add(existing)
    test_db.commit()

    real_query = test_db.query
    return_none_once = {"enabled": True}

    def fake_query(*entities, **kwargs):
        query = real_query(*entities, **kwargs)
        if entities == (DeviceToken,) and return_none_once["enabled"]:
            return _StaleDeviceTokenQueryProxy(
                query,
                return_none_once=return_none_once,
            )
        return query

    monkeypatch.setattr(test_db, "query", fake_query)
    monkeypatch.setattr(device_token_service.time, "sleep", lambda *_args, **_kwargs: None)

    record = DeviceTokenService.register_token(
        test_db,
        "user-new",
        token="device-token-123",
        platform="macos",
        environment="production",
        capabilities={"supports_live_activities": True},
    )
    test_db.commit()

    assert record.id == existing.id
    assert record.user_id == "user-new"
    assert record.platform == "macos"
    assert record.environment == "prod"
    assert record.capabilities == {"supports_live_activities": True}
    assert record.disabled_at is None

    rows = (
        test_db.query(DeviceToken)
        .filter(DeviceToken.token == "device-token-123")
        .all()
    )
    assert len(rows) == 1


def test_register_token_retries_duplicate_lookup_until_row_becomes_visible(
    test_db,
    monkeypatch,
):
    existing = DeviceToken(
        user_id="user-old",
        token="device-token-456",
        platform="ios",
        environment="dev",
        capabilities={"supports_live_activities": False},
        is_foreground=False,
        last_seen_at=None,
        disabled_at=None,
    )
    test_db.add(existing)
    test_db.commit()

    real_query = test_db.query
    invisible_lookups_remaining = {"count": 2}

    def fake_query(*entities, **kwargs):
        query = real_query(*entities, **kwargs)
        if entities == (DeviceToken,) and invisible_lookups_remaining["count"] > 0:
            return _DelayedVisibleDeviceTokenQueryProxy(
                query,
                invisible_lookups_remaining=invisible_lookups_remaining,
            )
        return query

    monkeypatch.setattr(test_db, "query", fake_query)
    record = DeviceTokenService.register_token(
        test_db,
        "user-new",
        token="device-token-456",
        platform="ios",
        environment="prod",
        capabilities={"supports_live_activities": True},
    )
    test_db.commit()

    assert record.id == existing.id
    assert record.user_id == "user-new"
    assert record.environment == "prod"
    assert record.capabilities == {"supports_live_activities": True}
