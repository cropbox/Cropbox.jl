# [Model Execution](@id model-execution)

The previous page explains how systems are defined and composed. This page
follows one executable system from configuration through construction, manual
updates, simulation, and output. Keeping those stages separate prevents many
common Cropbox mistakes.

## 1. Declare an executable system

```@example lifecycle
using Cropbox

@system Counter(Controller) begin
    increment             => 1              ~ preserve(parameter)
    limit                 => 3              ~ preserve(parameter)
    total(increment)                        ~ accumulate
    reached(total, limit) => total >= limit ~ flag
end
```

`@system` analyzes dependencies and creates a concrete Julia type. No model
instance exists yet.

## 2. Configure the runtime

### [Configuration](@id Config)

A `Config` maps system variables to scenario values. It is an input object, not
a model instance. Prefer `@config`, and use system types as keys when they are
available so parameter names and compatible units can be checked early.

```@example lifecycle
config = @config (
    Counter => (
        increment = 1,
        limit = 3,
    ),
    Clock => :step => 1u"hr",
)
```

Plain numeric values inherit the units declared by their parameters. Use an
explicit unit when the configuration performs a conversion or defines a time
step in a unit different from the declaration.

### [Context and Controller](@id Context)

Every constructed system receives a `Context` containing normalized
configuration and a `Clock`. The root `Controller` creates that context; child
systems receive it from their parent. Treat it as framework infrastructure and
configure public systems instead of mutating context fields.

### [Clock](@id Clock)

`Clock` tracks elapsed model time and update count. Its `step` controls model
updates. The later `snap` option controls only which updated states become
output rows, so numerical resolution and output frequency remain separate
decisions.

### [Calendar](@id Calendar)

`Calendar` maps elapsed time to a `ZonedDateTime` and date. Add or mix in a
component that uses it when a model depends on civil dates, time zones, or
date-indexed weather data.

```julia
config = @config (
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 4, 1, tz"UTC"),
)
```

`ZonedDateTime` and `tz"..."` are re-exported by Cropbox. Use the plain clock
when elapsed model time is sufficient.

## 3. Construct and initialize

```@example lifecycle
s = instance(Counter; config)
```

`instance` performs four user-visible actions:

1. initialize the random seed when `seed` is supplied;
2. normalize the supplied configuration;
3. construct the root system and its children;
4. call the initial `update!` needed to establish derived values.

This is why a freshly constructed instance already has meaningful `track` and
`flag` values.

## 4. Advance an existing instance

```@example lifecycle
update!(s)
(s.context.clock.time', s.total')
```

`update!` mutates the instance. Repeated calls continue from its current state.
This is useful for interactive control but must not be confused with a fresh
replicate.

## 5. Simulate and collect output

```@example lifecycle
result = simulate(Counter;
    config,
    stop = :reached,
    target = [:total, :reached],
)
```

`simulate` constructs a new instance and delegates the update loop to
`simulate!`. With the default snapshot rule, it collects the initialized state
and then each updated state until the stop condition is satisfied.

`simulate!` instead accepts an existing instance:

```@example lifecycle
short_config = @config(config, Counter => :limit => 2)
s2 = instance(Counter; config = short_config)
result2 = simulate!(s2; stop = :reached, target = :total)
```

Afterward, `s2` remains at the final simulated state.

## Stop conditions

`stop` is converted to a probe:

- an integer means a number of updates;
- a time quantity means a duration relative to the clock;
- a `Symbol` or string names a model value;
- a function receives the root instance and returns a value or Boolean.

```julia
simulate(Model; stop = 30u"d")
simulate(Model; stop = :mature)
simulate(Model; stop = "calendar.count")
simulate(Model; stop = s -> s.mass' >= 100u"g")
```

For an unknown-duration Boolean condition, Cropbox checks the condition before
each update. A duration is converted to an update count using `Clock.step` and
rounded up, so the final clock time can exceed a duration that is not an exact
multiple of the step. Design duration and threshold conditions with the model
time step in mind.

## Snapshot conditions

`snap` controls when rows are saved; it does not control when the model updates.

```julia
simulate(Model; stop = 30u"d", snap = 1u"d")
simulate(Model; stop = :mature, snap = :emerged)
simulate(Model; stop = :mature,
    snap = s -> Dates.hour(s.calendar.time') == 12)
```

A time quantity saves at clock intervals. The snapshot condition is tested once
on the initialized state and again after each update. Choose intervals compatible
with `Clock.step`; if no state satisfies the condition, the result can be empty.

## Update behaviors

The common behaviors occupy different points in an update:

- `preserve` is initialized during construction and normally stays fixed;
- `track` and `flag` are recalculated in dependency order;
- `accumulate`, `capture`, and `remember` carry values across updates;
- `provide` establishes a data source and `drive` selects the current input;
- `produce` may append child systems;
- `solve` and `bisect` repeat selected calculations to resolve an equation.

Tags such as `when`, `once`, `reset`, `min`, and `max` modify those transitions.
See [Behaviors and Tags](@ref behaviors-and-tags) for the supported combinations.

## Multiple configurations

When `configs` contains multiple scenarios, each scenario starts from a fresh
instance. Cropbox may execute scenarios on Julia threads. Do not let callbacks or
externally supplied mutable objects share unsafe global state between scenarios.

Use `seed` when stochastic parameters or dynamic structures must be reproducible.
The seed is reset for every scenario in the batch, which is useful for controlled
comparisons but may not be appropriate for independent Monte Carlo replicates;
run those replicates with explicit seeds.
