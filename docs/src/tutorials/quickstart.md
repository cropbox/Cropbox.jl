# [Quick Start](@id quick-start)

This tutorial builds a complete model, changes its parameters, runs it, and
selects useful output. It assumes basic Julia syntax but no previous Cropbox
experience.

## Load Cropbox

```@example quickstart
using Cropbox
```

Cropbox re-exports the `u"..."` unit string used throughout this manual.
Attaching units to model variables catches incompatible calculations early and
makes simulation output self-describing.

## Declare a model

The following system describes biomass increasing at a constant rate until a
target mass is reached.

```@example quickstart
@system Growth(Controller) begin
    rate: growth_rate    => 1.5            ~ preserve(parameter, u"g/hr")
    target: target_mass  => 5              ~ preserve(parameter, u"g")

    mass(rate)                             ~ accumulate(u"g")
    mature(mass, target) => mass >= target ~ flag
end
```

Read each declaration from left to right:

- `rate` and `target` are fixed values. The `parameter` tag makes them
  configurable.
- `mass` depends on `rate` and accumulates it using the simulation time step.
- `mature` is recalculated as a Boolean condition. Because `mass` only
  increases in this model, it remains true after the threshold is reached.
- `Controller` supplies configuration and a simulation clock to the top-level
  system.

Long names after `:` are aliases. They improve inspection output without making
equations verbose.

## Inspect defaults

Use `parameters` before running an unfamiliar model.

```@example quickstart
parameters(Growth)
```

`look` shows declarations and documentation. It accepts either a system type or
an instance.

```@example quickstart
look(Growth, :mass)
```

## Configure a scenario

Configuration keys form a system-variable-value path. A named tuple is a
convenient way to set several variables in one system.

```@example quickstart
config = @config (
    Growth => (rate = 2.0, target = 7.0),
    Clock => :step => 30u"minute",
)
```

Numbers supplied for unitful parameters are interpreted in the parameter's
declared unit. Explicit quantities are also accepted.

## Create an instance

```@example quickstart
s = instance(Growth; config)
```

`instance` initializes the full system and performs its initial update. Access a
variable with property syntax; postfix `'` retrieves the current value stored in
a Cropbox state.

```@example quickstart
s.mass', s.mature'
```

Calling `update!(s)` advances this same instance. Most analyses should use
`simulate`, which also collects output.

## Run the model

Stop on the model condition and request only the columns needed for the result.

```@example quickstart
result = simulate(Growth;
    config,
    stop = :mature,
    target = [:mass, :mature],
)
```

The initial state is included when the default snapshot rule is used. The
default index is `context.clock.time`, displayed as `time`.

To stop after a duration instead, pass a number or quantity.

```@example quickstart
simulate(Growth; config, stop = 2u"hr", target = :mass)
```

## Compare scenarios

`!` expands an iterable value into a vector of configurations.

```@example quickstart
configs = @config config + !(Growth => :rate => [1.0, 2.0, 3.0])

comparison = simulate(Growth;
    configs,
    stop = 4u"hr",
    target = :mass,
    meta = :Growth,
)
```

Metadata columns identify the configuration used for each run. For larger
experiments, request individual metadata pairs rather than every parameter in a
system.

## Plot output

`visualize` accepts the data frame returned by `simulate`.

```@example quickstart
visualize(result, :time, :mass; kind = :line)
```

It can also simulate a system and plot the result in one call:

```@example quickstart
visualize(Growth, :time, :mass;
    config,
    stop = 4u"hr",
    kind = :line,
)
```

## Next steps

- [How Cropbox Works](@ref cropbox-concepts) explains systems, dependencies, and
  behaviors.
- [Configure Models and Scenarios](@ref configuration-workflow) covers merging
  and factorial combinations.
- [Run Simulations and Shape Output](@ref simulation-workflow) covers nested
  paths, snapshots, callbacks, and output formats.
- [Build a Weather-driven Model](@ref phenology-tutorial) adds calendar time and
  tabular input.
