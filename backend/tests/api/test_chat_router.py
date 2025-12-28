import json

from api.config import settings
from api.routers import chat as chat_router


def _auth_headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {settings.bearer_token}"}


class FakeClaudeClient:
    def __init__(self, *_args, **_kwargs):
        pass

    async def stream_with_tools(self, *_args, **_kwargs):
        yield {"type": "token", "content": "Hello"}


def test_stream_chat_emits_token_and_complete(test_client, monkeypatch):
    monkeypatch.setattr(chat_router, "ClaudeClient", FakeClaudeClient)

    response = test_client.post(
        "/api/chat/stream",
        headers=_auth_headers(),
        json={"message": "Hi"},
    )
    assert response.status_code == 200

    body = response.text
    assert "event: token" in body
    assert json.dumps({"type": "token", "content": "Hello"}) in body
    assert "event: complete" in body
