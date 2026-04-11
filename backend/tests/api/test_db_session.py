from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from api.db import session as db_session


class _CloseFailingSession:
    def __init__(self) -> None:
        self.info: dict[str, object] = {}

    def close(self) -> None:
        raise OperationalError("close", {}, Exception("ssl connection closed"))


def test_get_db_does_not_fail_request_when_close_raises_operational_error(
    monkeypatch,
):
    app = FastAPI()
    app.dependency_overrides[db_session.get_current_user_id] = lambda: "user-123"

    @app.get("/probe")
    def probe(_db=Depends(db_session.get_db)):
        return {"ok": True}

    monkeypatch.setattr(db_session, "SessionLocal", lambda: _CloseFailingSession())
    monkeypatch.setattr(db_session, "set_session_user_id", lambda db, user_id: None)

    with TestClient(app) as client:
        response = client.get("/probe")

    assert response.status_code == 200
    assert response.json() == {"ok": True}
