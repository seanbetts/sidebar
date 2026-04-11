import inspect

from api.routers import events as events_router


def test_events_stream_route_has_no_db_dependency():
    parameters = inspect.signature(events_router.stream_events).parameters

    assert "db" not in parameters
