#!/usr/bin/env python3
"""Expose an existing Cropbox HTTP service as four MCP tools and resources."""

from __future__ import annotations

import argparse
import json
import os
from typing import Any
import urllib.error
import urllib.parse
import urllib.request

from mcp.server.fastmcp import FastMCP


def service_url(value: str) -> str:
    """Accept an HTTP(S) base URL, without embedded credentials or a query."""
    parsed = urllib.parse.urlsplit(value)
    if (parsed.scheme not in {"http", "https"} or not parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("provide an HTTP(S) service URL without credentials, query, or fragment")
    return value.rstrip("/")


def route_json(base_url: str, method: str, path: str,
               payload: dict[str, Any] | None = None, timeout: float = 120) -> dict[str, Any]:
    """Forward one request and retain the service's JSON values and error detail."""
    body = None if payload is None else json.dumps(payload, allow_nan=False).encode("utf-8")
    request = urllib.request.Request(
        base_url + path, data=body, method=method,
        headers={"Content-Type": "application/json"} if body is not None else {},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise ValueError(f"Cropbox {method} {path} returned HTTP {error.code}: {detail}") from error
    if not isinstance(result, dict):
        raise ValueError("the Cropbox route did not return a JSON object")
    return result


def create_mcp_adapter(url: str, name: str = "cropbox-service") -> FastMCP:
    """Register tools and read-only resources for one already-running service.

    The adapter does not start Julia or select a different model. Simulation
    arguments follow the request schema exposed by the configured HTTP service.
    """
    base_url = service_url(url)
    adapter = FastMCP(name)

    @adapter.tool()
    def describe_model() -> dict[str, Any]:
        """Discover the active model, variable paths, parameters, units, and table bindings."""
        return route_json(base_url, "GET", "/api/model")

    @adapter.tool()
    def simulate(request: dict[str, Any] | None = None) -> dict[str, Any]:
        """Run the active model. Read the schema resource for configuration, target, stop, and snap.

        Omitted fields retain the service defaults. Supply unit-aware values and
        CSV table content using the service's JSON request representation.
        """
        return route_json(base_url, "POST", "/api/simulate", request or {})

    @adapter.tool()
    def visualize(request: dict[str, Any]) -> dict[str, Any]:
        """Request an SVG visualization using x, y, kind, and simulation settings.

        The response contains the MIME type and SVG text. This operation executes
        the model and does not reuse a preceding simulation's results.
        """
        return route_json(base_url, "POST", "/api/visualize", request)

    @adapter.tool()
    def build_dashboard() -> dict[str, Any]:
        """Read generated dashboard metadata and the bundled dashboard URL."""
        return {"dashboard_url": base_url + "/dashboard",
                "schema": route_json(base_url, "GET", "/api/dashboard")}

    @adapter.resource("cropbox://service/model")
    def model_resource() -> str:
        """Model-specific metadata from GET /api/model."""
        return json.dumps(route_json(base_url, "GET", "/api/model"), ensure_ascii=False)

    @adapter.resource("cropbox://service/schema")
    def schema_resource() -> str:
        """Request and response schema fragments from GET /api/schema."""
        return json.dumps(route_json(base_url, "GET", "/api/schema"), ensure_ascii=False)

    @adapter.resource("cropbox://service/openapi")
    def openapi_resource() -> str:
        """HTTP route descriptions from GET /api/openapi."""
        return json.dumps(route_json(base_url, "GET", "/api/openapi"), ensure_ascii=False)

    @adapter.resource("cropbox://service/dashboard")
    def dashboard_resource() -> str:
        """Generated controls and plot presets from GET /api/dashboard."""
        return json.dumps(route_json(base_url, "GET", "/api/dashboard"), ensure_ascii=False)

    return adapter


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("CROPBOX_SERVICE_URL"),
                        help="URL of a running Cropbox serve() process")
    args = parser.parse_args()
    if not args.url:
        parser.error("--url or CROPBOX_SERVICE_URL is required")
    create_mcp_adapter(args.url).run(transport="stdio")


if __name__ == "__main__":
    main()
