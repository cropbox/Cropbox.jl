```@setup WebService
using Cropbox
```

# Web service

Cropbox can expose a system through HTTP with the same semantics as
`simulate()`, `visualize()`, `evaluate()` and `calibrate()`. The public
interface has three entry points:

* [`describe()`](@ref) projects systems, parameters, variables, docstrings,
  units and provided-table bindings into JSON-compatible values.
* [`serve()`](@ref) publishes that description and the model operations over HTTP.
* [`dashboard()`](@ref) starts the same service with a browser frontend.

Runnable chilling-forcing, leaf gas-exchange and Garlic services are provided in
[`examples/webapi`](https://github.com/cropbox/Cropbox.jl/tree/main/examples/webapi),
together with an optional Python MCP adapter.

## Inspect a model

```@example WebService
@system ServiceExample(Controller) begin
    "Configurable plant size."
    size => 2 ~ preserve(parameter, u"m")

    "Reported plant size."
    reported_size(size) => size ~ track(u"m")
end

model = describe(ServiceExample)
(
    name = model["model"]["name"],
    parameter = only(model["parameters"])["path"],
    unit = only(model["parameters"])["unit"],
    default = only(model["parameters"])["default"],
)
```

Every parameter, variable and table entry carries two kinds of paths: `path`
is the configuration path (`System.name`, with `declared` naming the same
parameter through the system that declared it) and `target` is the access path
used for `target`, `index`, `stop`, `x` and `y` in requests (`leaf.area`).
Parameters also report their declared `type`, `unit` and `default` value under
the server configuration; a `default` object can be sent back unchanged as a
configuration value. `GET /api/model` serves this description;
`GET /api/schema` and `GET /api/openapi` serve the generic request and response
structures, and `GET /api/docs` renders them with Swagger UI.

## Start a service

```julia
serve(ServiceExample; host="127.0.0.1", port=8000)
```

The equivalent dashboard-oriented entry point is `dashboard(ServiceExample)`.
Use `dashboard=:none` with `serve()` when only programming routes are needed,
and `async=true` to get the server object back instead of blocking.

`config` and `options` passed to `serve()` are the base for every request.
`request_defaults` holds trusted default request fields that are merged under
each client request; this is where a Julia `snap` function belongs, because
such a value never travels to the client. A `config` given there in the JSON
shape of a request (for example a bundled weather table as CSV) is decoded once
and becomes part of the base configuration:

```julia
serve(ServiceExample;
    config=:ServiceExample => :size => 3u"m",
    request_defaults=Dict("stop" => Dict("value" => 24, "unit" => "hr")),
)
```

A client field replaces the corresponding default. Configurations are merged
per parameter, so a client value for one parameter leaves the rest of the base
configuration in place. Default `snap` settings are not applied to `evaluate`
and `calibrate`, which align observations themselves.

## Requests

```json
{
  "config": {"ServiceExample.size": {"value": 300, "unit": "cm"}},
  "stop": {"value": 4, "unit": "hr"},
  "target": ["reported_size"]
}
```

* `config` accepts flat `{"System.name": value}` entries, nested
  `{"System": {"name": value}}` objects, or a mix. A parameter is addressed by
  name or alias, through its system or the mixin that declared it; an unknown
  parameter of a described system is rejected. `configs` runs several
  configurations (each merged over `config`) and stacks the results.
* Values are plain JSON values or objects `{"value", "unit", "type"}`; `value`
  may be an array. Values are converted to the given unit before they reach the
  model, and strings are coerced to the parameter's declared type.
* `target` and `index` take variable paths as strings or arrays; `leaf.*`
  selects every variable of a system and an object maps output column names to
  paths. `base` names a system (`leaf`) that those paths are then relative to.
  Unknown paths are rejected, except indexed ones such as `leaves[1].area`,
  which only resolve at run time.
* `meta` adds columns: a system name contributes that system's configured
  parameters, which tells the runs of `configs` apart, and an object
  contributes constant columns.
* `stop` and `snap` take a count, a `{value, unit}` duration or the path of a
  count or condition variable.
* `evaluate` and `calibrate` additionally take `observed` (a table), `metric`
  and, for calibration, `parameters` with `[lower, upper]` or
  `{lower, upper, unit}` bounds keyed like `config`.
* `visualize` takes `x`, `y`, `kind`, `xstep` and plot options under `plot`,
  and either simulates the model or plots a table passed as `data`, whose
  columns `x` and `y` then name.

Responses carry `status`, `contract_version` and the result. Simulation tables
list `columns` (name, type, unit) and `rows` of plain values; non-finite numbers
are `null`. Errors use HTTP 400 for malformed JSON, 404/405 for routing, 422 for
a request that cannot be decoded or does not match the model, and 500 for
failures while the model runs, with a JSON `error` object.

## Tables

A `provide` parameter accepts CSV content or row arrays. Column metadata
(`type`, `unit`, `timezone`) declares what cannot be inferred from the values;
CSV headers may alternatively carry `name (unit)` or `name (:Type)` annotations
when no `columns` are given. Header annotations are parsed as units and an
allowlisted set of type names, never evaluated.

```json
{
  "config": {
    "Weather.s": {
      "type": "CSV",
      "content": "index,Tair\n2024-01-01T00:00:00+09:00,4.2\n",
      "columns": [
        {"name": "index", "type": "ZonedDateTime", "timezone": "Asia/Seoul"},
        {"name": "Tair", "type": "Float64", "unit": "°C"}
      ]
    }
  }
}
```

Timestamps may carry their own offset; `timezone` converts them to the named
zone and is required for local timestamps without an offset. Temporal columns
cannot carry a unit. The table entries of the model description list the index
column and the columns read by `drive` variables, with their units, so a client
can construct a replacement table. Table parameters only accept table payloads;
a bare string is rejected.

## Dashboard

`GET /api/dashboard` derives dashboard metadata from the description: one
editable control per parameter and table input (plus the runtime `Clock.step`),
selectable outputs, default plot panels and the simulation defaults. Service
profiles customize it through `ui`:

```julia
dashboard(ServiceExample; ui=Dict(
    "title" => "Plant size",
    "outputs" => ["reported_size"],
    "panels" => [Dict("x" => "time", "y" => ["reported_size"], "kind" => "line")],
    "stop" => Dict("value" => 24, "unit" => "hr"),
    "table_inputs" => [],   # label, default_filename and columns for provided tables
))
```

The bundled browser dashboard reads this metadata and calls the same operation
routes as any other client.

## Deployment boundary

The server executes model operations supplied by trusted application code. It
has no authentication, authorization, TLS termination, request quotas or job
queue. Bind it to loopback for local work, or place it behind a gateway that
supplies those controls. Swagger UI at `/api/docs` loads its assets from a
public CDN; the OpenAPI document at `/api/openapi` is served locally.
