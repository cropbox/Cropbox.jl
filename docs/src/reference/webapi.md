# [Web API](@id web-api)

```@docs
describe
serve
dashboard
```

The rest of this page specifies contract `0.2.0` of the HTTP interface. A
running service has the same specification as an OpenAPI document at
`GET /api/openapi`, which `GET /api/docs` renders with Swagger UI. The
[Web service](@ref web-service) guide walks through a first service.

## Routes

| Route | Result |
| --- | --- |
| `GET /api/model` | the [model description](@ref web-api-description) under the configuration of the service |
| `GET /api/dashboard` | the [dashboard metadata](@ref web-api-dashboard) |
| `GET /api/schema` | the route table, and the schemas of the OpenAPI document as `definitions` |
| `GET /api/openapi` | the OpenAPI document |
| `GET /api/docs`, `GET /docs` | Swagger UI for that document |
| `POST /api/simulate` | a table |
| `POST /api/visualize` | a plot as SVG |
| `POST /api/evaluate` | the value of a metric against observations |
| `POST /api/calibrate` | a calibrated configuration |
| `GET /`, `GET /dashboard` | the bundled dashboard page, unless `dashboard` moved or disabled it |

Requests are stateless, and nothing in a request is evaluated as code.

## [Model description](@id web-api-description)

`describe()` returns, and `GET /api/model` serves, an object with `contract`
(its `version`), `model` (`name`, `module`), `systems`, `parameters`,
`variables` and `tables`. The entries of the last three share these fields:

| Field | Meaning |
| --- | --- |
| `system`, `name`, `alias` | where the variable is declared and what it is called |
| `path` | configuration path, `System.name`, under which a parameter is set |
| `declared` | the same path through the system that declared the variable, which differs for a mixin |
| `target` | access path used as `target`, `index`, `stop`, `x` and `y`, such as `leaf.area`; `null` without a fixed path |
| `description` | the docstring |
| `state`, `type`, `unit` | the declared state (`preserve`, `track`, ...), type and unit |
| `role` | `parameter`, `table` (a `provide` input), `output` or `internal` |
| `tags`, `dependencies` | public tags of the declaration, and the variables it reads |
| `default` | parameters only: the value in effect under the configuration of the service, as a value object that can be sent back |
| `index`, `columns` | tables only: the index column, and the columns that `drive` variables read, with their units |

A variable is an `output` when its state holds a value (`track`, `accumulate`,
`integrate`, `advance`, `remember`, `flag` and the like) and `internal`
otherwise (a `call`, a `produce`d system). A system that the model only
`produce`s while it runs is described too. Its parameters are configured like
any other, but it has no fixed access path: its `path` in `systems` and the
`target` of its parameters are `null`, and its other variables are not listed.
The context is left out, apart from the parameters that the configuration
sets, such as the clock step.

## [Requests](@id web-api-requests)

| Field | Operations | Value |
| --- | --- | --- |
| `config` | all | parameter values; see [Configurations](@ref web-api-config) |
| `configs` | simulate, evaluate, calibrate | an array of configurations, each merged over `config`; the results are stacked |
| `target`, `index` | simulate, evaluate, calibrate | [variable paths](@ref web-api-names) for the columns of the result and its index |
| `base` | all | the path of a system (`leaf`) that variable paths are then relative to |
| `meta` | simulate, evaluate, calibrate | extra columns: a system name adds the configured parameters of that system, which tells the runs of `configs` apart; an object adds constant columns; an array combines them |
| `stop` | all | an update count (number), a duration (`{"value", "unit"}` in a unit of the clock time), or the path of a count or condition variable (string) |
| `snap` | simulate, visualize | when a row is recorded: an interval (`{"value", "unit"}`, not a bare number), a boolean, or the path of a condition variable |
| `seed` | simulate, evaluate, calibrate | an integer for the random number generator |
| `nounit`, `long` | simulate | booleans: a table without units, a table in long format |
| `observed` | evaluate, calibrate | a [table](@ref web-api-tables) of observations, with the index columns and the targets |
| `metric` | evaluate, calibrate | `rmse` (the default), `nrmse`, `rmspe`, `mae`, `mape`, `ef` or `dr` |
| `parameters` | calibrate | bounds for each parameter to calibrate: `[lower, upper]` or `{"lower", "upper", "unit"}`, keyed like `config`. Bounds may be in any unit of the parameter, and the calibrated value comes back in its declared unit. A path that several systems share through a mixin is calibrated through the path of one of them |
| `weight`, `pareto` | calibrate | weights of several targets, and whether to return the Pareto frontier of them |
| `optim` | calibrate | options for the optimizer (`MaxSteps`, `Method` and so on), except those that write files where the service runs |
| `x`, `y`, `kind`, `plot`, `xstep`, `data` | visualize | see [Plots](@ref web-api-plots) |

A field that an operation does not have is rejected, as is an unknown field of
a value object, a table, `plot` or `xstep`. A misspelled request does not
quietly run with defaults.

### [Values](@id web-api-values)

A value is a plain JSON value, or an object with a `value` and optionally its
`unit`, `type` and `timezone`:

```json
{"value": 300, "unit": "cm"}
```

* `value` may be an array, or an array of rows for a `tabulate` or
  `interpolate` parameter.
* `unit` is a label such as `m`, `K*d`, `m*s^-1` or `°C`. Responses write
  units in ASCII and in a form that requests read back.
* `type` names a Julia type. `Bool`, `Int`, `Float64`, `String`, `Symbol`,
  `Date`, `DateTime` and `ZonedDateTime` convert the value on input; any other
  name is informative.
* `timezone` is the IANA zone of a `ZonedDateTime`. A time without an offset
  requires it, and a time in a zone with daylight saving time carries it, so
  that the zone survives the round trip.

### [Configurations](@id web-api-config)

`config` takes flat `{"System.name": value}` entries, nested
`{"System": {"name": value}}` objects, or a mix of them. A parameter is
addressed by its name or alias, under its system or a mixin of it. A flat path
may name the system with its modules (`Main.Plant.Leaf.a`) to tell it from a
system of the same name in another module; the plain name sets both. Clients
set the parameters that the model declares, the clock and produced systems
included; any other path is rejected.

A value is checked against its parameter before the model is built:

* a parameter of a scalar type takes one value, not an array. A plain number
  is in its declared unit, and a quantity is converted to that unit; a unit
  that does not convert, or any unit for a parameter without one, is rejected;
* a string is read as the declared type of the parameter;
* nested arrays are the rows of the matrix that a `tabulate` or `interpolate`
  parameter takes;
* a table input takes a [table](@ref web-api-tables), and nothing else does.

### [Variable paths](@id web-api-names)

`target` and `index` take a path, an array of paths, or an object that maps
output column names to paths. Paths go by name or alias; `*` and `leaf.*`
select every variable of a system, and `time` is the clock time. Unknown paths
are rejected, except indexed ones such as `leaves[1].area`, which only resolve
while the model runs.

### [Tables](@id web-api-tables)

A table is CSV text or columns with row arrays:

```json
{
  "type": "CSV",
  "content": "index,Tair\n2024-01-01T00:00:00+09:00,4.2\n",
  "columns": [
    {"name": "index", "type": "ZonedDateTime", "timezone": "Asia/Seoul"},
    {"name": "Tair", "type": "Float64", "unit": "°C"}
  ]
}
```

```json
{"type": "DataFrame", "columns": [{"name": "time", "unit": "hr"}, {"name": "height", "unit": "cm"}], "rows": [[0, 0.0], [1, 0.5]]}
```

* `columns` declare what the values do not tell: `type`, `unit` and
  `timezone`. A CSV header may carry `name (unit)` or `name (:Type)`
  annotations instead when no `columns` are given. Annotations are parsed as
  units and as the type names above, never evaluated, and a column name that
  still ends in parentheses is rejected.
* Timestamps may carry their own offset. `timezone` converts them to the named
  zone and is required for local timestamps without an offset. A temporal
  column cannot carry a unit.
* Column names are unique, and a row has no more cells than there are columns,
  so no value is dropped. A cell that is absent or `null` is a missing value.
* The table of a simulation response is itself a table of the second kind and
  can be sent back as it is: as `data` to plot, or as `observed`.

The `tables` of the model description list, for each `provide` input, the index
column and the columns that `drive` variables read, so that a client can build
a replacement.

## [Defaults](@id web-api-defaults)

A request starts from what `serve()` was given, and what a client sends wins:

1. `config` of `serve()` is the base configuration.
2. The `config` of `request_defaults` is merged over it once, when the service
   starts. `GET /api/model` reports the result as the `default` of each
   parameter.
3. The `config` of a request is merged over that, and each of `configs` over
   the result.

At every step a value replaces the one below it for the same parameter,
whichever of the parameter's names (its alias, a mixin of its system) either
used, and the parameters that the upper configuration does not set keep their
values.

The other `request_defaults` (`stop`, `snap`, `target`, ...) stand in for the
fields that a request leaves out. A default only applies to the operations
that have the field: `snap` is not a field of `evaluate` and `calibrate`,
which align observations themselves. Defaults are trusted and may hold Julia
values that no request can express, such as a `snap` function.

`options` of `serve()`, the constructor options that give a system its
`extern` values, reach every operation that runs the model. A request cannot
set them.

## [Plots](@id web-api-plots)

`POST /api/visualize` draws one table, `y` against `x`:

| Field | Value |
| --- | --- |
| `x` | one variable or column; `time` by default |
| `y` | one variable or column, or an array of them |
| `kind` | `scatter` (the default), `line`, `scatterline` or `step` |
| `plot` | options: `title`, `xlab`, `ylab`, `legend`, `legendpos`, `names`, `colors`, `xlim` and `ylim` (`[lower, upper]`, either may be `null`), `xunit`, `yunit`, `aspect`, and `linestyle` (`solid`, `dash`, `dot`, `dashdot` or `dashdotdot`; one, or one for each of `y`) |
| `data` | a [table](@ref web-api-tables) to plot as it is; `x` and `y` then name its columns |
| `config`, `base`, `stop`, `snap` | without `data`: the simulation whose table is plotted |
| `xstep` | without `data`: a parameter to vary, `{"path", "start", "stop", "step", "unit"}` or `{"path", "values", "unit"}`, for one simulation per value |

A single `y` is named on its axis and several in a legend. The series of one
plot share an axis, so their units have to convert to each other.

This is the table form of `visualize()`. Its other forms have no request: a
`group`, several systems or configurations side by side, observations against
estimates, a response surface over two parameters, and layers added with
`visualize!`. For those, request the tables and draw them in the client, or
call Julia.

## [Responses](@id web-api-responses)

Every response carries `status` and `contract_version`.

* A simulation returns a table: `columns` (`name`, `type`, `unit`) and `rows`
  of plain values, with `null` for non-finite numbers and missing values, and
  a `summary` with `nrow` and `elapsed_ms`.
* A plot returns `format` (`svg`), `content_type` and the SVG text in `body`.
* An evaluation returns `metric`, `target` and `value`, a value object with
  its unit, or an array of them for several targets.
* A calibration returns `config`, nested objects of value objects in the
  declared units of their parameters, keyed by metric values when `pareto` is
  set.

### [Errors](@id web-api-errors)

```json
{
  "status": "error",
  "contract_version": "0.2.0",
  "error": {"code": "invalid_request", "category": "validation", "message": "Unknown parameter `Plant.zzz`", "retryable": false, "path": "/api/simulate"}
}
```

| Status | `category` | `code` | When |
| --- | --- | --- | --- |
| 400 | `syntax` | `invalid_request` | the body is not a JSON object |
| 404 | `routing` | `not_found` | there is no such route |
| 405 | `method` | `method_not_allowed` | the route does not take the method |
| 422 | `validation` | `invalid_request` | the model or its data cannot take the request |
| 500 | `execution` | `execution_failed` | the model failed while it ran |

A 422 is the client's to correct: an unknown field, parameter or variable, a
value in a unit or shape that its parameter does not take, a `stop` or `snap`
that is no duration, a table that would lose values, observations that match
no output or lack the target, labels or units that a plot cannot take. A 500
reports the cause of a failure inside the model, without a stack trace.

## [Dashboard metadata](@id web-api-dashboard)

`GET /api/dashboard` serves what the bundled page is built from, for any other
frontend to use:

| Field | Content |
| --- | --- |
| `title`, `model` | the title of the page and the `name` and `module` of the model |
| `controls` | one for each parameter and table input, and the runtime `Clock.step`: `path`, `label`, `kind` (`number`, `checkbox`, `text` or `file`), `unit`, `default`, `value_type`, `min`, `max` and `step`, among others |
| `outputs` | the variables to choose from, the clock `time` first, as entries of the model description |
| `tables` | the table entries of the model description |
| `simulation` | the `stop` and `snap` of the request defaults, as a request takes them; five units of the clock time for `stop` when the service has none, and `null` for a `snap` that it has not or that only Julia can express |
| `panels` | plots of `outputs`: `title`, `x`, `y`, `kind`, and optionally `linestyles`, `xmin`, `xmax`, `ymin`, `ymax` and `xstep`, the path of a sweep |
| `sweeps` | parameter sweeps for panels: the fields of `xstep`, with an optional `label` |

`ui` of `serve()` and `dashboard()` arranges it:

| Key | Effect |
| --- | --- |
| `title` | the title |
| `outputs` | the variables offered, by target, name or alias; parameters may be among them |
| `panels` | the plot panels; their variables are added to the outputs, so that one simulation can feed every panel |
| `sweeps` | the sweeps that panels refer to by `xstep` |
| `table_inputs` | `label`, `description`, `accept`, `columns` and `default_filename` for the control of a table input, found by its `path` |

A name that the model does not have, or a key that `ui` does not have, is an
error when the service starts.
