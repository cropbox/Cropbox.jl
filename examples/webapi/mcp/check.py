#!/usr/bin/env python3
"""Verify an actual MCP stdio round trip against a running example service.

This is a protocol check, not an LLM experiment. Requires the example HTTP server.
"""

import argparse
import asyncio
import json
from pathlib import Path
import sys

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def check(url: str, target: str, x: str) -> None:
    process = StdioServerParameters(command=sys.executable,
        args=[str(Path(__file__).with_name("adapter.py")), "--url", url])
    async with stdio_client(process) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            resources = await session.list_resources()
            assert {tool.name for tool in tools.tools} == {"describe_model", "simulate", "visualize", "build_dashboard"}
            assert {str(r.uri) for r in resources.resources} == {
                f"cropbox://service/{name}" for name in ("model", "schema", "openapi", "dashboard")}
            for resource in resources.resources:
                result = await session.read_resource(resource.uri)
                assert json.loads(result.contents[0].text)
            for name, arguments in (
                ("describe_model", {}),
                ("simulate", {"request": {"target": [target]}}),
                ("visualize", {"request": {"x": x, "y": [target], "kind": "line"}}),
                ("build_dashboard", {}),
            ):
                result = await session.call_tool(name, arguments)
                assert not result.isError, result
                payload = json.loads(result.content[0].text)
                if name == "simulate":
                    assert payload["status"] == "ok" and payload["rows"]
                if name == "visualize":
                    assert payload["content_type"] == "image/svg+xml" and "<svg" in payload["body"]
                print(f"{name}: ok")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--target", default="F")
    parser.add_argument("--x", default="time")
    args = parser.parse_args()
    asyncio.run(check(args.url, args.target, args.x))
