```@setup WebService
using Cropbox
```

# [Web service](@id web-service)

A Cropbox system can be served over HTTP as it is. The service reads what the
model declares and offers `simulate()`, `visualize()`, `evaluate()` and
`calibrate()` as JSON requests, with a browser dashboard on top of them. This
page follows one model from its definition to a served result that a client
uses again. The [Web API](@ref web-api) reference specifies every request and
response.

Three functions do the work:

* [`describe()`](@ref) lists what a model declares as JSON-compatible values;
* [`serve()`](@ref) publishes that description and the model operations over HTTP;
* [`dashboard()`](@ref) starts the same service for its bundled browser page.

Complete services for chilling and forcing, leaf gas exchange and Garlic are in
[`examples/webapi`](https://github.com/cropbox/Cropbox.jl/tree/main/examples/webapi),
together with an optional MCP adapter.

## Define a model

Nothing in a model is written for the service. Docstrings, units and aliases
are what a client gets to see, so they are worth having:

```@example WebService
@system Plant(Controller) begin
    "Height gained per hour."
    r: growth_rate => 0.5 ~ preserve(parameter, u"cm/hr")

    "Plant height."
    h(r): height          ~ accumulate(u"cm")
end
nothing # hide
```

## Describe it

```@example WebService
model = describe(Plant)
(
    parameter = only(model["parameters"])["path"],
    alias     = only(model["parameters"])["alias"],
    unit      = only(model["parameters"])["unit"],
    default   = only(model["parameters"])["default"],
    outputs   = [v["target"] for v in model["variables"]],
)
```

`describe()` is all the service knows about the model, and `GET /api/model`
serves it. Every entry carries two paths. `path` is the configuration path
(`Plant.r`), under which a client sets a parameter. `target` is the access
path (`h` here, `leaf.area` in a nested model), by which requests name
variables as `target`, `index`, `stop`, `x` and `y`. An alias stands in for a
name in both. A parameter also reports its declared type and unit and its
`default`, the value in effect under the configuration of the service, which a
client can send back as it is. [Model description](@ref web-api-description)
lists the fields.

## Serve it

```julia
serve(Plant; port=8000)        # the API, and the dashboard at http://127.0.0.1:8000/
dashboard(Plant; port=8000)    # the same service, named for its page
```

Either call blocks until it is interrupted. `async=true` returns the server
object instead, `dashboard=:none` leaves the page out, and `dashboard="/ui"`
serves it at a path of its own.

What a service is started with is where every request begins:

```julia
serve(Plant;
    config = :Plant => :r => 2u"cm/hr",
    request_defaults = Dict("stop" => Dict("value" => 3, "unit" => "d")),
)
```

* `config` is the base configuration. The `config` of a request is merged over
  it parameter by parameter: the client's value wins, whichever of the
  parameter's names (its alias, a mixin of its system) either side used, and
  the rest of the base stays as it is.
* `request_defaults` stand in for the fields that a request leaves out, such
  as `stop` or `target`. They are trusted, so a Julia `snap` function belongs
  here; it never travels to a client. A `config` among them, in the JSON shape
  of a request (a bundled weather table as CSV, say), is merged over the base
  configuration once, when the service starts.
* `options`, the constructor options that give a system its `extern` values,
  are the service's alone. A request has no field for them.

[Defaults](@ref web-api-defaults) has the exact rules.

## Send a request

Every operation is a `POST` with a JSON body. This simulation sets the growth
rate by its alias and in another unit:

```sh
curl -H 'Content-Type: application/json' http://127.0.0.1:8000/api/simulate -d '{
  "config": {"Plant.growth_rate": {"value": 10, "unit": "mm/hr"}},
  "stop": {"value": 3, "unit": "hr"},
  "target": ["height"]
}'
```

```json
{
  "status": "ok",
  "contract_version": "0.2.0",
  "model": "Plant",
  "type": "DataFrame",
  "columns": [
    {"name": "time", "type": "Float64", "unit": "hr"},
    {"name": "height", "type": "Float64", "unit": "cm"}
  ],
  "rows": [[0.0, 0.0], [1.0, 1.0], [2.0, 2.0], [3.0, 3.0]],
  "summary": {"nrow": 4, "elapsed_ms": 2}
}
```

The rate arrived in millimetres, replaced the 2 cm/hr of the service, and the
model ran in its own unit. The table names the unit of every column, and its
rows are plain values.

`evaluate` and `calibrate` take the same fields and a table of observations;
`visualize` returns an SVG. A request that the model cannot take, such as a
misspelled field, an unknown parameter or a value in a unit that does not
convert, is answered with HTTP 422 and a message rather than run with
defaults. [Requests](@ref web-api-requests) and [Errors](@ref web-api-errors)
have the details.

## Use the result again

A simulation response is a table in the shape that requests take. A client
keeps it and sends it back instead of asking the model again. As `data`, it is
plotted without a second simulation:

```json
{
  "data": {"type": "DataFrame", "columns": [...], "rows": [...]},
  "x": "time",
  "y": "height",
  "kind": "line"
}
```

`POST /api/visualize` answers with the SVG text in `body`. The same table
saves as CSV with `name (unit)` headers, which a request reads back with their
units.

The HTTP operation draws one table, `y` against `x`. Groups, layers,
observations against estimates and response surfaces are forms of
`visualize()` for Julia callers only; see [Plots](@ref web-api-plots).

## Dashboard

`dashboard(Plant)` serves the bundled page at `/`. The page is a client of the
routes above, built from `GET /api/dashboard`: a control for every parameter
and table input, the outputs to choose from, the plot panels, and the `stop`
and `snap` of the request defaults to start from. `ui` arranges it:

```julia
dashboard(Plant;
    request_defaults = Dict("stop" => Dict("value" => 3, "unit" => "d")),
    ui = Dict(
        "title" => "Plant height",
        "outputs" => ["height"],
        "panels" => [Dict("x" => "time", "y" => ["height"], "kind" => "line")],
    ),
)
```

Outputs and panel variables are named by target, name or alias and may be
parameters, for example a threshold drawn as a reference line. A name that the
model does not have is an error when the service starts.
[Dashboard metadata](@ref web-api-dashboard) lists the other keys.

## Deployment boundary

The server executes model operations supplied by trusted application code. It
has no authentication, authorization, TLS termination, request quotas or job
queue. Bind it to loopback for local work, or place it behind a gateway that
supplies those controls. Swagger UI at `/api/docs` loads its assets from a
public CDN; the OpenAPI document at `/api/openapi` is served locally.

Requests are data: clients set only parameters that the model declares, tables
come only from the content they send, and nothing in a request is evaluated as
code. A model can still declare a parameter that names a file for it to read,
as the `filename` of the store systems (`DataFrameStore` and its relatives)
does. Any client can set such a parameter, so serve those models to trusted
clients only.
