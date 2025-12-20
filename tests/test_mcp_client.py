#!/usr/bin/env python3
"""Test client for MCP Streamable HTTP protocol."""
import asyncio
import httpx
import json
import os
from typing import AsyncIterator, Dict, Any


class MCPClient:
    """Simple MCP Streamable HTTP client for testing."""

    def __init__(self, base_url: str, bearer_token: str):
        self.base_url = base_url.rstrip('/')
        self.bearer_token = bearer_token
        self.session_id = None

    def _get_headers(self, accept: str = "application/json") -> Dict[str, str]:
        """Get headers with authentication."""
        headers = {
            "Authorization": f"Bearer {self.bearer_token}",
            "Content-Type": "application/json",
            "Accept": accept
        }
        # Add session ID if we have one
        if self.session_id:
            headers["mcp-session-id"] = self.session_id
        return headers

    def _parse_sse_response(self, text: str) -> Dict[str, Any]:
        """Parse Server-Sent Events response."""
        lines = text.strip().split('\n')
        data_lines = [line[6:] for line in lines if line.startswith('data: ')]
        if data_lines:
            return json.loads(data_lines[0])
        return {}

    async def initialize_session(self) -> Dict[str, Any]:
        """Initialize an MCP session."""
        async with httpx.AsyncClient() as client:
            # Try to initialize with POST to /mcp
            response = await client.post(
                f"{self.base_url}/mcp",
                headers=self._get_headers("application/json, text/event-stream"),
                json={
                    "jsonrpc": "2.0",
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2024-11-05",
                        "capabilities": {},
                        "clientInfo": {
                            "name": "test-client",
                            "version": "1.0.0"
                        }
                    },
                    "id": 1
                }
            )

            print(f"Initialize response status: {response.status_code}")

            if response.status_code == 200:
                # Extract session ID from headers
                self.session_id = response.headers.get("mcp-session-id")
                print(f"Session ID: {self.session_id}")

                # Parse SSE response
                result = self._parse_sse_response(response.text)
                return result
            else:
                raise Exception(f"Failed to initialize: {response.text}")

    async def list_tools(self) -> Dict[str, Any]:
        """List all available tools."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/mcp",
                headers=self._get_headers("application/json, text/event-stream"),
                json={
                    "jsonrpc": "2.0",
                    "method": "tools/list",
                    "id": 2
                }
            )

            print(f"\nList tools response status: {response.status_code}")

            if response.status_code == 200:
                return self._parse_sse_response(response.text)
            else:
                raise Exception(f"Failed to list tools: {response.text}")

    async def call_tool(self, tool_name: str, arguments: Dict[str, Any]) -> Dict[str, Any]:
        """Call a specific tool."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.base_url}/mcp",
                headers=self._get_headers("application/json, text/event-stream"),
                json={
                    "jsonrpc": "2.0",
                    "method": "tools/call",
                    "params": {
                        "name": tool_name,
                        "arguments": arguments
                    },
                    "id": 3
                }
            )

            print(f"\nCall tool response status: {response.status_code}")

            if response.status_code == 200:
                return self._parse_sse_response(response.text)
            else:
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
