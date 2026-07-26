# [Simulation](@id Simulation1)

The simulation API separates four jobs: construct a model, advance it, collect
selected values, and compare those values with observations.

| Function | Main role | Result |
|---|---|---|
| `instance` | construct and initialize one model | a mutable system instance |
| `simulate` | construct fresh instances and run them | one `DataFrame`, or one per layout |
| `simulate!` | continue an existing instance | one `DataFrame`, or one per layout |
| `evaluate` | join observations and estimates and calculate metrics | one number or a tuple |
| `calibrate` | search parameter bounds against those metrics | a `Config` or Pareto frontier |

For a first simulation, read [Systems and Simulation Lifecycle](@ref
simulation-lifecycle) and [Run Simulations and Shape Output](@ref
simulation-workflow). This page records the complete public call patterns and
the less common options exercised by the test suite.

## Construct one model with `instance`

```julia
instance(SystemType;
    config = (),
    options = (),
    seed = nothing,
)
```

`instance` normalizes `config`, calls the generated system constructor, and
runs the initialization update. It returns the model itself, not a table.

- `config` supplies values declared as parameters.
- `options` is a named tuple of constructor resources, typically for `extern`
  or `override` declarations that are not ordinary parameters.
- `seed` initializes Julia's random generator before configuration values are
  sampled and before the system is constructed.

Prefer a system type as a configuration key when it is in scope. Type keys
check parameter names and convert compatible units immediately. Symbol or
string keys remain useful when loading configuration before the system package,
but validation is then deferred until construction.

## Run fresh models with `simulate`

```julia
simulate(SystemType; keywords...) -> DataFrame
simulate(SystemType, layout; keywords...) -> Vector{DataFrame}
simulate(SystemType, layout, configs; keywords...) -> Vector{DataFrame}
simulate(; system = SystemType, keywords...) -> DataFrame
simulate(f, SystemType, ...; keywords...) -> DataFrame
```

The last positional callback form is do-block syntax for `snatch`:

```julia
simulate(Model; stop = 10u"d") do rows, model
    rows[1][:count] = length(model.organs')
end
```

With no `stop`, `snap`, `snatch`, or `callback`, `simulate` returns the
initialized snapshot and performs no time-step update. This fast snapshot form
is useful for static response models and parameter grids.

### Construction keywords

| Keyword | Default | Meaning |
|---|---:|---|
| `config` | `()` | one configuration, or a shared base for `configs` |
| `configs` | `[]` | scenario patches or complete configurations |
| `parameters` | `()` | a compact parameter sweep with automatic metadata |
| `options` | `()` | named constructor resources passed to every instance |
| `seed` | `nothing` | random seed reset before each fresh instance |

When both `config` and `configs` are present, Cropbox merges the shared
`config` into every entry of `configs`, with the scenario entry taking
precedence. `parameters` is a convenience sweep: Cropbox expands its iterable
values and adds the selected parameter values as metadata. Do not combine
nonempty `parameters` and `configs`; construct the configurations explicitly
when a design needs both.

```julia
simulate(ResponseModel;
    config = Clock => :step => 1u"d",
    parameters = ResponseModel => :temperature => 5:5:30,
    target = :rate,
)
```

Batch runs may use Julia threads. Keep callbacks free of unsynchronized writes
to shared state. A `seed` makes each scenario reproducible, but it is reset to
the same value for every scenario; run an explicit seed loop when replicates
must use distinct random streams.

## Output layout

A simple call supplies one layout through keywords:

```julia
simulate(Model;
    base = nothing,
    index = :time => "context.clock.time",
    target = [:LAI, :biomass],
    meta = [:Treatment, :replicate => 1],
    stop = 100u"d",
)
```

| Keyword | Default | Meaning |
|---|---:|---|
| `base` | `nothing` | system or bundle relative to which selectors are resolved |
| `index` | clock time | columns that identify output rows |
| `target` | simple root values | model values to collect |
| `meta` | none | configuration values or constants copied to every row |

Selectors accept:

- a symbol such as `:LAI`;
- a string path such as `"calendar.date"`;
- a renamed pair such as `:date => "calendar.date"`;
- a tuple or vector of selectors;
- `"*"` for root fields or `"soil.*"` for one nested system's fields.

The left side of a pair is the output column and the right side is the model
path. Explicit targets make downstream code stable when a model later gains
new variables. Wildcards are best reserved for inspection.

Only simple scalar output is collected automatically: numbers, symbols,
strings, and date/time values. Arrays, dictionaries, tuples, DataFrames, and
nested systems are omitted. Add a scalar summary declaration or use `snatch`
for those objects.

`meta=:Treatment` copies every configured entry under that system name.
`meta=(:Treatment, :replicate => 1)` combines configured values with an
explicit constant column. Metadata comes from configuration, not from the
current state of a changing model variable.

### Several layouts in one run

Pass a vector of named tuples when different tables should be collected from
the same update sequence:

```julia
layout = [
    (index = :time, target = [:LAI, :biomass]),
    (base = :soil, index = :depth, target = [:water, :root_length]),
    (target = :mature, meta = (:site => "A",)),
]

tables = simulate(Model, layout; config, stop = :finished)
```

Each layout may contain `base`, `index`, `target`, and `meta`; omitted entries
use the same defaults as a simple call. The result order matches the layout
order. With a separate positional `configs` vector, each returned table
combines the corresponding layout across all scenarios.

## Stop and snapshot conditions

`stop` determines how long the model advances. It accepts:

| Form | Meaning |
|---|---|
| integer or real number | that many update calls |
| time quantity | enough updates to reach or pass the duration, using `Clock.step` |
| symbol or string | read a numeric, time, or Boolean model variable |
| function `model -> value` | calculate the same kinds of condition |
| Boolean model condition | keep updating until it becomes true |

A numeric stop is interpreted once as an update count. A Boolean stop is tested
before every update. If the stop threshold is already true after
initialization, no update is made.

`snap` decides which initialized or updated states become output rows:

| Form | Meaning |
|---|---|
| `nothing` | save every state |
| time quantity | save at elapsed-time multiples measured from `Clock.init` |
| symbol or string | save when that model value is true |
| function `model -> Bool` | save when the callback is true |

`Clock.step` still controls every numerical update. `snap=1u"d"` does not turn
an hourly model into a daily model; it only keeps every 24th hourly state. The
initialized state is included whenever the snapshot condition is true, so a
run with `stop=10` normally has 11 rows.

## Custom snapshot processing

`snatch(rows, model)` runs for every saved state. `rows` contains one extracted
row per matching base-system item and may be edited, extended, or emptied.
This is the intended extension point for dynamic structures such as root
architectures.

`callback(model, simulation_layout)` runs after a saved state has been
processed. The second argument is Cropbox's internal simulation accumulator.
It is lower level and more sensitive to implementation changes than `snatch`;
prefer `snatch` unless coordination with the accumulator is necessary. The
current callback path runs after updated snapshots, not after the initial
snapshot; `snatch` receives both initial and updated snapshots.

Supplying either callback disables the fastest column-oriented collection
path. That is normally insignificant for complex callback work, but it matters
for large scalar-only sweeps.

## Output formatting

| Keyword | Default | Meaning |
|---|---:|---|
| `nounit` | `false` | strip units from returned columns |
| `long` | `false` | stack target columns into variable/value rows |
| `verbose` | `true` | show a progress display |

`nounit=true` changes only the returned table. Model calculations remain
unit-aware. Long format preserves index columns, stacks all remaining columns,
and sorts by the index. Request it only when a plotting or statistics workflow
needs tidy long data, since it can greatly increase the row count.

## Continue one model with `simulate!`

```julia
simulate!(instance; layout_keywords..., run_keywords...) -> DataFrame
simulate!(instance, layout; run_keywords...) -> Vector{DataFrame}
simulate!(f, instance, ...; run_keywords...) -> DataFrame
```

`simulate!` continues the exact instance passed to it. It accepts output,
stop/snapshot, callback, and formatting keywords, but not a new `config`,
`options`, or `seed`. Use it for deliberate staged runs or manual management;
use `simulate(SystemType, ...)` for independent treatments and replicates.

```julia
s = instance(Model; config, seed = 1)
first_stage = simulate!(s; stop = :emerged, target = :biomass)
second_stage = simulate!(s; stop = :mature, target = :biomass)
```

The second stop is evaluated from the already advanced state. The two returned
tables are separate. Each call saves its current state first when the snapshot
condition is true, so the stage boundary can appear in both tables.

## Compare data with `evaluate`

```julia
evaluate(observations, estimates;
    index,
    target,
    metric = :rmse,
)

evaluate(SystemType, observations;
    config = (), configs = [],
    index = nothing,
    target,
    metric = :rmse,
    simulation_keywords...,
)
```

For two tables, `target=:observed => :estimated` maps different column names.
For a system, the same name is assumed unless a pair is supplied. Multiple
targets return a tuple in target order.

Cropbox normalizes compatible index units, inner-joins rows on the index, drops
missing target pairs in the two-table form, and then applies the metric. It does
not compare rows merely because they have the same position.

| Symbol | Metric | Result scale |
|---|---|---|
| `:rmse` | root mean square error | target unit |
| `:nrmse` | RMSE divided by observation mean | dimensionless |
| `:rmspe` | root mean square percentage error | dimensionless |
| `:mae` | mean absolute error | target unit |
| `:mape` | mean absolute percentage error | dimensionless |
| `:ef` | Nash–Sutcliffe efficiency | dimensionless |
| `:dr` | refined index of agreement | dimensionless |

`metric` may also be a function `(estimate, observation) -> score`. Relative
metrics need special care near zero. Efficiency metrics need enough variation
in the observations to define their denominator.

When evaluating several configurations, residuals are combined across their
matching rows before one score per target is calculated. Give environment or
treatment columns in `index` when otherwise identical dates must remain
distinct.

## Search parameters with `calibrate`

```julia
calibrate(SystemType, observations;
    config = (), configs = [],
    index = nothing,
    target,
    parameters,
    metric = :rmse,
    weight = nothing,
    pareto = false,
    optim = (),
    simulation_keywords...,
)
```

`parameters` has the shape of a configuration, but each value is a two-value
search bound:

```julia
parameters = Model => (
    base_temperature = (-5u"°C", 15u"°C"),
    thermal_requirement = (100u"K*d", 2000u"K*d"),
)
```

Bounds are converted to each declared parameter unit before optimization. The
result is a `Config` containing the selected values in model units.

Cropbox uses
[BlackBoxOptim.jl](https://github.com/robertfeldt/BlackBoxOptim.jl)
differential-evolution methods. `optim` is a named tuple forwarded to
`bboptimize`; Cropbox defaults are `MaxSteps=5000` and `TraceInterval=10`.
Immediately before calling `bboptimize`, Cropbox calls `Random.seed!(0)`, so
optimizer initialization is deterministic. This is framework behavior rather
than a BlackBoxOptim option. Set an explicit search budget in scripts so runtime
does not depend on defaults.

With one target, calibration minimizes that target's metric. With several
targets, it uses a multi-objective method. `weight` changes how a single
compromise is chosen from objective values. `pareto=true` returns an ordered
mapping from objective tuples to configurations along the Pareto frontier
instead of one `Config`.

Local or gradient-based methods are not selected through `calibrate`. When they
are appropriate, construct and test an explicit objective with `evaluate` and
pass it to an optimization package such as
[Optim.jl](https://github.com/JuliaNLSolvers/Optim.jl).

Do not pass nonempty `config` and `configs` together to `evaluate` or
`calibrate`. For several environments, make each entry of `configs` complete
and include environment-identifying columns in `index`. See [Evaluation and
Calibration](@ref evaluation-tutorial) for validation splits, residual checks,
and reporting practice.

## API docstrings

```@docs
instance
simulate
simulate!
evaluate
calibrate
```
