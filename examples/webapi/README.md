# Web API examples

Three services built with the same `describe`, `serve` and `dashboard`
functions. This page says how to run them. What a service does is in the
[Web service guide](https://cropbox.github.io/Cropbox.jl/dev/guide/webservice/),
and what its routes take and return in the
[Web API reference](https://cropbox.github.io/Cropbox.jl/dev/reference/webapi/).

| Application | Shows | Input |
| --- | --- | --- |
| `cherry` | Units, aliases, parameter overrides and accumulated states | Fixed synthetic seasonal temperatures |
| `gasexchange` | Coupled component paths and response-curve presets | Package physiology with specified weather conditions |
| `garlic` | CSV replacement of a provided table and dated whole-plant outputs | Normalized CUH weather and package KM/CUH/P2 presets |

Run the commands below from the root of this checkout.

## Prepare the environment

```sh
julia --project=examples/webapi -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
```

The environment installs the registered Garlic and LeafGasExchange packages
and uses Cropbox from this checkout. The first load and the first plot take
longer while Julia compiles.

## Run a service

```sh
julia --project=examples/webapi examples/webapi/server.jl cherry 8000
```

Replace `cherry` with `gasexchange` or `garlic`. Open
<http://127.0.0.1:8000/dashboard> and use the Run button; Ctrl+C stops the
server. Services bind to loopback only.

From a Julia session, the same service without blocking it:

```julia
using Cropbox
include("examples/webapi/profiles.jl")

p = WebAPIExamples.profile("cherry")
server = serve(p.system; p.config, p.ui, p.request_defaults, port=8000, async=true)
close(server)   # when finished
```

`profiles.jl` holds what is specific to each application: the configuration,
the request defaults and the panels of its dashboard.

## Call the routes

With the cherry service running:

```sh
curl http://127.0.0.1:8000/api/model
curl http://127.0.0.1:8000/api/dashboard
curl http://127.0.0.1:8000/api/openapi
curl -H 'Content-Type: application/json' -d '{"target":["C","F","m"]}' http://127.0.0.1:8000/api/simulate
curl -H 'Content-Type: application/json' -d '{"x":"time","y":["C","F"],"kind":"line"}' http://127.0.0.1:8000/api/visualize
```

Swagger UI is at <http://127.0.0.1:8000/api/docs>.

## Optional MCP adapter

The adapter is a separate Python process that forwards requests to a running
Cropbox service. It executes no Julia and holds no model. Its four tools and
four read-only resources (`cropbox://service/...`) are MCP identifiers, not
additional HTTP routes.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r examples/webapi/mcp/requirements.txt
.venv/bin/python examples/webapi/mcp/adapter.py --url http://127.0.0.1:8000
```

An MCP host launches that command with absolute paths to the Python
executable and `adapter.py`, and talks to it over standard input and output.
No API key or LLM is needed to test the connection.

## Verification

`Pkg.test()` covers the model description, the JSON codec, request handling,
the operations and loopback HTTP round trips with small models
(`test/framework/webapi.jl`). The checks that load Garlic and LeafGasExchange
run by hand in the example environment:

```sh
julia --project=. -e 'using Pkg; Pkg.test()'
julia --project=examples/webapi examples/webapi/integration.jl
julia --project=examples/webapi examples/webapi/check.jl
.venv/bin/python -m unittest discover -s examples/webapi/mcp
```

* `integration.jl` drives the three services with the requests that the
  bundled dashboard sends, without a socket, and compares the cherry and
  gas-exchange tables with native `simulate` calls.
* `check.jl` starts each service on a loopback port and exercises its routes
  over HTTP. With `CROPBOX_MCP_PYTHON="$PWD/.venv/bin/python"` set, it also
  runs the MCP protocol check against each of them.
* The unit tests of the adapter need no running service.

To check the MCP protocol against one running service:

```sh
.venv/bin/python examples/webapi/mcp/check.py --url http://127.0.0.1:8000
```

For gas exchange add `--target A_net --x Ci`, and for Garlic
`--target total_mass --x DAP`. The check reads every resource and calls every
tool; it does not evaluate an LLM.

## Data and scope

The cherry temperatures are illustrative, not observations. The Garlic CSV in
`test/examples/data/garlic` was converted from
[`Garlic.jl v0.1.29`, `data/CUH/2014.wea`](https://github.com/cropbox/Garlic.jl/blob/v0.1.29/data/CUH/2014.wea)
(MIT license); `convert.jl` in that directory reproduces it. The physiological
parameters of the gas-exchange package are used as they are.

These examples are for trusted local modeling work. Authentication, upload and
execution limits, TLS termination, monitoring and job management belong in a
deployment layer in front of a service that others can reach.
