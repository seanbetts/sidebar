#!/usr/bin/env python3
"""Test client for MCP Streamable HTTP protocol."""

import asyncio
import json
import os
from typing import Any

import httpx
from fastapi.testclient import TestClient


class MCPClient:
    """Simple MCP Streamable HTTP client for testing."""

    def __init__(
        self,
        base_url: str,
        bearer_token: str,
        http_client: httpx.AsyncClient | None = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.bearer_token = bearer_token
        self.session_id = None
        self.http_client = http_client

    def _get_headers(self, accept: str = "application/json") -> dict[str, str]:
        """Get headers with authentication."""
        headers = {
            "Authorization": f"Bearer {self.bearer_token}",
            "Content-Type": "application/json",
            "Accept": accept,
        }
        # Add session ID if we have one
        if self.session_id:
            headers["mcp-session-id"] = self.session_id
        return headers

    def _parse_sse_response(self, text: str) -> dict[str, Any]:
        """Parse Server-Sent Events response."""
        lines = text.strip().split("\n")
        data_lines = [line[6:] for line in lines if line.startswith("data: ")]
        if data_lines:
            return json.loads(data_lines[0])
        return {}

    async def _post(self, payload: dict[str, Any], accept: str) -> httpx.Response:
        """Post MCP requests with either a shared or ad-hoc client."""
        if self.http_client is not None:
            return await self.http_client.post(
                f"{self.base_url}/mcp",
                headers=self._get_headers(accept),
                json=payload,
            )

        async with httpx.AsyncClient() as client:
            return await client.post(
                f"{self.base_url}/mcp",
                headers=self._get_headers(accept),
                json=payload,
            )

    async def initialize_session(self) -> dict[str, Any]:
        """Initialize an MCP session."""
        response = await self._post(
            {
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "test-client", "version": "1.0.0"},
                },
                "id": 1,
            },
            "application/json, text/event-stream",
        )

        print(f"Initialize response status: {response.status_code}")

        if response.status_code == 200:
            # Extract session ID from headers
            self.session_id = response.headers.get("mcp-session-id")
            print(f"Session ID: {self.session_id}")

            # Parse SSE response
            result = self._parse_sse_response(response.text)
            return result
        raise Exception(f"Failed to initialize: {response.text}")

    async def list_tools(self) -> dict[str, Any]:
        """List all available tools."""
        response = await self._post(
            {"jsonrpc": "2.0", "method": "tools/list", "id": 2},
            "application/json, text/event-stream",
        )

        print(f"\nList tools response status: {response.status_code}")

        if response.status_code == 200:
            return self._parse_sse_response(response.text)
        raise Exception(f"Failed to list tools: {response.text}")

    async def call_tool(
        self, tool_name: str, arguments: dict[str, Any]
    ) -> dict[str, Any]:
        """Call a specific tool."""
        response = await self._post(
            {
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": arguments},
                "id": 3,
            },
            "application/json, text/event-stream",
        )

        print(f"\nCall tool response status: {response.status_code}")

        if response.status_code == 200:
            return self._parse_sse_response(response.text)
        raise Exception(f"Failed to call tool: {response.text}")


class SyncMCPClient:
    """Synchronous MCP Streamable HTTP client for tests."""

    def __init__(self, client: TestClient, bearer_token: str):
        self.client = client
        self.bearer_token = bearer_token
        self.session_id = None

    def _get_headers(self, accept: str = "application/json") -> dict[str, str]:
        headers = {
            "Authorization": f"Bearer {self.bearer_token}",
            "Content-Type": "application/json",
            "Accept": accept,
        }
        if self.session_id:
            headers["mcp-session-id"] = self.session_id
        return headers

    def _parse_sse_response(self, text: str) -> dict[str, Any]:
        lines = text.strip().split("\n")
        data_lines = [line[6:] for line in lines if line.startswith("data: ")]
        if data_lines:
            return json.loads(data_lines[0])
        return {}

    def initialize_session(self) -> dict[str, Any]:
        response = self.client.post(
            "/mcp",
            headers=self._get_headers("application/json, text/event-stream"),
            json={
                "jsonrpc": "2.0",
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {
                        "name": "test-client",
                        "version": "1.0.0",
                    },
                },
                "id": 1,
            },
        )

        if response.status_code == 200:
            self.session_id = response.headers.get("mcp-session-id")
            return self._parse_sse_response(response.text)
        raise Exception(f"Failed to initialize: {response.text}")

    def list_tools(self) -> dict[str, Any]:
        response = self.client.post(
            "/mcp",
            headers=self._get_headers("application/json, text/event-stream"),
            json={"jsonrpc": "2.0", "method": "tools/list", "id": 2},
        )

        if response.status_code == 200:
            return self._parse_sse_response(response.text)
        raise Exception(f"Failed to list tools: {response.text}")

    def call_tool(self, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        response = self.client.post(
            "/mcp",
            headers=self._get_headers("application/json, text/event-stream"),
            json={
                "jsonrpc": "2.0",
                "method": "tools/call",
                "params": {"name": tool_name, "arguments": arguments},
                "id": 3,
            },
        )

        if response.status_code == 200:
            return self._parse_sse_response(response.text)
        raise Exception(f"Failed to call tool: {response.text}")


async def main():
    """Test the MCP endpoint."""
    # Get configuration from environment
    bearer_token = os.getenv("BEARER_TOKEN")
    if not bearer_token:
        print("ERROR: BEARER_TOKEN environment variable not set")
        print("Run with: doppler run -- python tests/test_mcp_client.py")
        return

    base_url = "http://localhost:8001"

    print("=" * 60)
    print("MCP Streamable HTTP Client Test")
    print("=" * 60)

    client = MCPClient(base_url, bearer_token)

    try:
        # Test 1: Initialize session
        print("\n[Test 1] Initializing MCP session...")
        init_result = await client.initialize_session()
        print(f"✓ Session initialized: {json.dumps(init_result, indent=2)}")

    except Exception as e:
        print(f"✗ Initialize failed: {e}")
        print("\nTrying without session initialization...")

    try:
        # Test 2: List available tools
        print("\n[Test 2] Listing available tools...")
        tools_result = await client.list_tools()
        print(f"✓ Tools listed: {json.dumps(tools_result, indent=2)}")

    except Exception as e:
        print(f"✗ List tools failed: {e}")

    try:
        # Test 3: Call fs_list tool
        print("\n[Test 3] Calling fs_list tool...")
        call_result = await client.call_tool("fs_list", {"path": ".", "pattern": "*"})
        print(f"✓ Tool called: {json.dumps(call_result, indent=2)}")

    except Exception as e:
        print(f"✗ Call tool failed: {e}")

    print("\n" + "=" * 60)
    print("Test complete!")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
