# Web API examples

Three applications use the same `describe`, `serve`, and `dashboard` functions.
Run the following commands from the root of this checkout.

## Prepare the Julia environment

```sh
julia --project=examples/webapi -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
```

The environment installs registered Garlic and LeafGasExchange versions and uses
Cropbox from this checkout. It does not use a globally installed Cropbox version.
The first load and first plot can take longer while Julia compiles the code.

## Inspect and run

```sh
julia --project=examples/webapi
```

```julia
using Cropbox
include("examples/webapi/profiles.jl")

p = WebAPIExamples.profile("cherry")
metadata = describe(p.system; config=p.config)
metadata["parameters"]

server = serve(p.system; config=p.config, ui=p.ui,
    request_defaults=p.request_defaults, port=8000, async=true)

# When finished, release the listening socket.
close(server)
```

`async=true` returns the server handle without blocking the Julia caller. It does
not create an asynchronous simulation job queue. For an API without a web
frontend, pass `dashboard=:none` to `serve`. The equivalent UI-oriented call is
`dashboard(p.system; config=p.config, ui=p.ui, request_defaults=p.request_defaults)`.

For a blocking process, choose one application:

```sh
julia --project=examples/webapi examples/webapi/server.jl cherry 8000
```

Replace `cherry` with `gasexchange` or `garlic`. Open
<http://127.0.0.1:8000/dashboard>, then use the Run button. Ctrl+C stops the server.
Use a different port if one is already occupied. Services bind to loopback only.

| Application | Main interface feature | Input |
| --- | --- | --- |
| `cherry` | Units, aliases, parameter overrides, and accumulated states | Fixed synthetic seasonal temperatures |
| `gasexchange` | Coupled component paths and response-curve presets | Package physiology with specified weather conditions |
| `garlic` | CSV replacement of a provided table and dated whole-plant outputs | Normalized CUH weather and package KM/CUH/P2 presets |

The cherry series is illustrative, not observational validation data. The Garlic
CSV is distributed in `test/examples/data/garlic`, with its source and offline
conversion script. HTTP requests and the dashboard use CSV, not the WEA parser.
Physiological parameters in the gas-exchange package are not adjusted here.

## Call the routes

With the cherry service running:

```sh
curl http://127.0.0.1:8000/api/model
curl http://127.0.0.1:8000/api/schema
curl http://127.0.0.1:8000/api/openapi
curl http://127.0.0.1:8000/api/dashboard
curl -H 'Content-Type: application/json' -d '{"target":["C","F","m"]}' http://127.0.0.1:8000/api/simulate
curl -H 'Content-Type: application/json' -d '{"x":"time","y":["C","F"],"kind":"line"}' http://127.0.0.1:8000/api/visualize
```

Simulation responses contain columns, units, and rows. Visualization responses
contain `content_type` and SVG text in `body`. Swagger UI is available at
`/api/docs` and loads its assets from a public CDN. The model service and bundled
dashboard do not require a separate frontend build.

Application-specific defaults and panel presets belong in `profiles.jl`. A
custom frontend can consume `/api/model`, `/api/schema`, and `/api/dashboard`
and call the same execution routes. `dashboard()` uses the bundled HTML frontend
by default. The separate Stipple experiment is not a dependency of this package.

## Optional MCP adapter

The adapter is a separate Python process. It forwards requests to an already
running Cropbox service. It does not execute Julia or implement another model.
It provides four tools and four read-only resources with `cropbox://service/`
identifiers. These are MCP identifiers, not additional HTTP routes.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r examples/webapi/mcp/requirements.txt
.venv/bin/python examples/webapi/mcp/adapter.py --url http://127.0.0.1:8000
```

An MCP host should launch that command using the absolute paths to the Python
executable and `adapter.py`. The host communicates over standard input/output,
and the adapter communicates with Cropbox over HTTP. Model settings follow the
JSON schemas exposed by the service. No API key or LLM is needed to test this
connection. Using an LLM requires an independently configured MCP-capable host.

## Verification

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=examples/webapi examples/webapi/check.jl
.venv/bin/python -m unittest discover -s examples/webapi/mcp
```

To test the live MCP protocol, leave the cherry HTTP server running and use:

```sh
.venv/bin/python examples/webapi/mcp/check.py --url http://127.0.0.1:8000
```

For gas exchange use `--target A_net --x Ci`, or for Garlic use
`--target total_mass --x DAP`. The protocol check reads all resources and calls
all tools. It is not an LLM reliability evaluation.

To check the HTTP and MCP protocols for all three models in one run, after
installing the optional Python dependencies:

```sh
CROPBOX_MCP_PYTHON="$PWD/.venv/bin/python" julia --project=examples/webapi examples/webapi/check.jl
```

This starts and closes a loopback service for each example. The Web API example
CI job runs the same checks on Linux.

These examples target trusted local modeling work. Authentication, upload and
execution limits, TLS termination, monitoring, and job management belong in a
deployment layer before exposing a service to untrusted users.
