```@setup WebService
using Cropbox
```

# Web service

Cropbox can expose a system through the same metadata and simulation semantics
used by `simulate()` and `visualize()`. The public interface has three entry
points:

* [`describe()`](@ref) projects system, parameter, variable, docstring, unit,
  and provided-table metadata into JSON-compatible values.
* [`serve()`](@ref) publishes that contract and the model operations over HTTP.
* [`dashboard()`](@ref) starts the same service with a browser frontend.

## Inspect a model

Runnable chilling-forcing, leaf gas-exchange, and Garlic services are provided in
[`examples/webapi`](https://github.com/cropbox/Cropbox.jl/tree/webapi/examples/webapi).
That directory includes an isolated Julia environment, HTTP checks, and an
optional Python MCP adapter. The examples use the Cropbox checkout directly.

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
    parameter = only(model["parameters"])["config_path"],
    unit = only(model["parameters"])["unit"],
)
```

`GET /api/model` contains only model-specific discovery fields. These are the
contract version, model identity, systems, parameters, variables, and table
bindings. Generic request structures are available from `GET /api/schema`, and
`GET /api/openapi` associates those structures with HTTP routes. Clients can
therefore inspect a model without receiving a second copy of route metadata.

## Start a service

The default call serves the programming API and bundled dashboard and blocks
until the server stops.

```julia
serve(ServiceExample; host="127.0.0.1", port=8000)
```

The equivalent dashboard-oriented entry point is:

```julia
dashboard(ServiceExample; host="127.0.0.1", port=8000)
```

Use `dashboard=:none` with `serve()` when only programming routes are needed.
Set `async=true` for tests or applications that manage the returned HTTP server
object themselves.

## Values, units, and tables

Scalar values can include an explicit unit:

```json
{
  "config_entries": [
    {"path": "ServiceExample.size", "value": {"value": 3, "unit": "m"}}
  ],
  "stop": {"value": 4, "unit": "hr"},
  "target": ["reported_size"]
}
```

When a request specifies a compatible unit, the service converts the numeric
value to that unit before it is passed to Cropbox or returned in a response.
Non-finite floating-point results are represented as JSON `null`, because JSON
does not define numeric literals for `NaN` or infinity.

A `provide` parameter accepts a `DataFrame`, row-based JSON, or CSV content.
CSV requests should include column metadata when names alone do not determine
the units expected by downstream `drive` variables. For compatibility with
existing Cropbox data, the service also recognizes simple `name (unit)` headers
and an allowlisted set of type annotations such as `date (:Date)`. Arbitrary
expressions in CSV headers are never evaluated. New clients should place unit,
type, and time-zone declarations in the structured `columns` metadata.

```json
{
  "config_entries": [{
    "path": "Weather.s",
    "value": {
      "type": "CSV",
      "filename": "weather.csv",
      "content": "index,Tair\n2024-01-01T00:00:00+09:00,4.2\n",
      "columns": [
        {"name": "index", "type": "ZonedDateTime", "timezone": "Asia/Seoul"},
        {"name": "Tair", "type": "Float64", "unit": "°C"}
      ]
    }
  }]
}
```

Timestamp strings may carry their own UTC offset. A `timezone` field converts
those instants to the named zone and is required for local timestamps without
an offset. The DSL alias `datetime` denotes `ZonedDateTime`. Declare `::DateTime`
explicitly for a timestamp without a time zone. JSON values use the corresponding
Julia type name in their `type` field, not the DSL alias.
Dashboard profiles can declare the same metadata through
`ui["table_inputs"]`, along with a label and the name of a server-configured
default CSV. The browser uses this declaration when it builds an uploaded CSV
request.

Package-specific source formats should be normalized before the service starts.
The HTTP contract remains CSV-based and does not require clients to implement a
model package's private file parser.

The model description identifies a table parameter as `TableInput` but does
not serialize a default `DataFrame` held by the server configuration. The
table binding entries report the accepted path, target path, index, consumer
columns, and units needed to construct a replacement.
Only client-relevant DSL tags are published. Internal clock wiring and
macro-generated initialization tags remain implementation details.

`Clock.step` is emitted by the dashboard schema as a runtime configuration
control retaining the configured value and unit. The time output uses the
clock's declared unit, which is hours for `Clock` and days for `DailyClock`.
A model-defined `time` output retains its own metadata, for example a calendar
timestamp. The step control is derived by the service rather
than synthesized by the browser and remains distinct from parameters extracted
from the model DSL. Likewise, `controls` contains one entry per editable
CSV/DataFrame input, whereas `tables` may contain several descriptors when
nested systems consume the same `provide` input through different access paths.

The dashboard `simulation` object carries the service defaults for `stop` and
`snap`. A stop value without a unit is an update count, a value with a unit is
a duration, and a string identifies a model variable used as a stop condition.
Snapshot settings may retain the trusted service default, supply a quantity
interval, or identify a model condition. Selecting the service default omits
`snap` from the browser request so `request_defaults` remains authoritative.
Default and client `config_entries` are merged by configuration path. An
uploaded table therefore replaces the server's CSV entry for the same
`provide` path while unrelated default entries remain in the request.

The model explorer groups editable entries by their declared system. Its add
action selects a system and then a declared parameter or table, activates that
entry, and moves directly to its editor. Clearing the entry removes it from the
next request. Hovering or focusing the state icon beside an entry shows its
description and structured metadata, including the default value, unit, type,
path, and dependencies when available. Undeclared configuration paths are not
offered because the service cannot validate their value type or unit from model
metadata.

Panel axes choose values from one simulation result. A trusted service profile
may also assign an `xstep` preset to a panel so that `visualize` repeatedly runs
the model over declared parameter values. This supports response curves such as
assimilation against intercellular carbon dioxide or temperature. The bundled
browser renders these preset panels but does not expose an editor for grouped
parameter values.

## Deployment boundary

The server executes model operations supplied by trusted application code.
`request_defaults` is intended for trusted server-side values such as a Julia
`snap` function and is not serialized to clients. The built-in server does not
provide authentication, authorization, TLS termination, request quotas, or a
job queue. Bind it to loopback for local work, or place it behind a production
gateway that supplies those controls.

Swagger UI is available at `/api/docs`. Its assets are loaded from a public CDN;
the underlying OpenAPI document at `/api/openapi` remains available without the
UI.
