# [Systems and Simulation Lifecycle](@id simulation-lifecycle)

Many Cropbox surprises come from mixing up declaration time, construction time,
and update time. This page follows one system through its full lifecycle.

## 1. Declare a system type

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

## 2. Construct and initialize

```@example lifecycle
s = instance(Counter)
```

`instance` performs four user-visible actions:

1. initialize the random seed when `seed` is supplied;
2. normalize the supplied configuration;
3. construct the root system and its children;
4. call the initial `update!` needed to establish derived values.

This is why a freshly constructed instance already has meaningful `track` and
`flag` values.

## 3. Advance an existing instance

```@example lifecycle
update!(s)
(s.context.clock.time', s.total')
```

`update!` mutates the instance. Repeated calls continue from its current state.
This is useful for interactive control but must not be confused with a fresh
replicate.

## 4. Simulate and collect output

```@example lifecycle
result = simulate(Counter; stop = :reached, target = [:total, :reached])
```

`simulate` constructs a new instance and delegates the update loop to
`simulate!`. With the default snapshot rule, it collects the initialized state
and then each updated state until the stop condition is satisfied.

`simulate!` instead accepts an existing instance:

```@example lifecycle
s2 = instance(Counter; config = Counter => :limit => 2)
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
- `solve`, `bisect`, and experimental `fixedpoint` repeat selected calculations
  to resolve an equation.

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
