#!/usr/bin/env python3
"""Things bridge service (macOS)."""
import os
from fastapi import FastAPI, Header, HTTPException, status


app = FastAPI(title="sideBar Things Bridge", version="0.1.0")

BRIDGE_TOKEN = os.getenv("THINGS_BRIDGE_TOKEN", "")


def require_token(x_things_token: str | None = Header(default=None)) -> None:
    if not BRIDGE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="THINGS_BRIDGE_TOKEN is not set",
        )
    if not x_things_token or x_things_token != BRIDGE_TOKEN:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid bridge token")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.get("/lists/{scope}")
async def get_list(scope: str, x_things_token: str | None = Header(default=None)) -> dict:
    require_token(x_things_token)
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Not implemented")


@app.post("/apply")
async def apply_operation(request: dict, x_things_token: str | None = Header(default=None)) -> dict:
    require_token(x_things_token)
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail="Not implemented")


if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("THINGS_BRIDGE_PORT", "8787"))
    uvicorn.run(app, host="127.0.0.1", port=port)
