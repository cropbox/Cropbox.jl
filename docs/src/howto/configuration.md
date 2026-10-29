# [Configure Models and Scenarios](@id configuration-workflow)

Configuration keeps equations separate from experimental conditions. A Cropbox
configuration maps a system key and parameter name to a value.

## Inspect configurable values first

```@example configflow
using Cropbox
using DataFrames

@system Experiment(Controller) begin
    rate: growth_rate     => 1 ~ preserve(parameter, u"g/hr")
    initial: initial_mass => 2 ~ preserve(parameter, u"g")
    mass(rate)                 ~ accumulate(init = initial, u"g")
end

parameters(Experiment)
```

Use `alias=true` for long names and `recursive=true` to include parameters from
embedded systems. `exclude` can remove infrastructure systems from a recursive
listing.

```@example configflow
parameters(Experiment; alias = true, recursive = true, exclude = (Context,))
```

## Set one or more parameters

These forms are equivalent:

```@example configflow
c1 = @config Experiment => (:rate => 2, :initial => 3)
c2 = @config Experiment => (rate = 2, initial = 3)
c1 == c2
```

Cropbox also accepts a symbol such as `:Experiment` as the system key. Prefer
the system type when it is available in scope: `Experiment` must resolve to a
real Julia binding, and Cropbox immediately validates the parameter name and
unit against that system's declarations. A symbol key defers those checks until
the configuration is applied to a model. Symbols remain useful for
configurations loaded from text formats or assembled dynamically before the
model package is loaded. Inspect the accepted surface with
`parameters(Experiment)`.

Values without units are interpreted in the unit declared by the variable.
Supplying explicit compatible quantities is clearer when configurations cross
files or packages.

## [Sample stochastic parameters with `±`](@id stochastic-configuration)

```julia
mean ± standard_deviation
```

Cropbox interprets this value as a Normal draw when a state is initialized.
Units may be attached to the entire expression:

```julia
config = @config RootType => (
    growth_rate = (6.0 ± 0.6)u"cm/d",
    angle = 70 ± 10,
)

s = instance(RootModel; config, seed = 1)
```

This is a sampling specification, not a general uncertainty-propagation
number. Once sampled, the state contains one ordinary value. Use `seed` for a
reproducible draw, and use an explicit seed loop when independent replicates
are needed. The [CropRootBox tutorial](@ref croprootbox-tutorial) shows this
pattern in a dynamic root model.

## Merge configurations

Later values override earlier values.

```@example configflow
base      = @config Experiment => (rate = 1, initial = 2)
treatment = @config Experiment => :rate => 3
combined  = @config base + treatment
```

Use this ordering consistently: package defaults, site or cultivar defaults,
experiment settings, and finally the smallest treatment patch.

## Expand a parameter sweep

Prefix `!` expands one iterable into separate configurations.

```@example configflow
rates = @config base + !(Experiment => :rate => 1:3)
length(rates)
```

A literal vector is useful when scenarios are not generated from one range:

```@example configflow
explicit_rates = @config [
    Experiment => :rate => 1,
    Experiment => :rate => 3,
]
length(explicit_rates)
```

Pass the result as `configs`, not `config`.

```@example configflow
simulate(Experiment;
    configs = rates,
    stop = 2u"hr",
    target = :mass,
    meta = :Experiment,
)
```

## Build factorial combinations

`*` forms the Cartesian product of configuration patches.

```@example configflow
design = @config (
    Experiment => :rate    => [1, 2]
) * (
    Experiment => :initial => [0, 10]
)
length(design)
```

The values associated with `*` are treated as collections to expand. Use `!`
when only one factor is needed.

## Configure infrastructure

Built-in systems are configured like model systems.

```julia
@config (
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 1, 1, tz"UTC"),
)
```

The special system key `:0` targets the root controller name. It is useful in
generic workshop code but an explicit system name is easier to maintain in a
published model.

## Supply tables and external values

Parameters are not limited to scalars. `provide(parameter)` commonly receives a
DataFrame through configuration, while a system with an `extern` variable may
receive an object through constructor `options` instead.

```julia
config = @config Weather => :data => weather
s = instance(RootArchitecture; config, options = (; box = container))
```

Configuration is declarative input. `options` are constructor keywords and may
carry resources that are not normal model parameters. The distinction matters
for reproducibility: store configuration when possible, and document every
external option explicitly.

## Normalize units at data boundaries

`unitfy` reads compatible units and simple type annotations from DataFrame
column names. This pattern is useful for workshop data and CSV files whose
headers carry their schema.

```@example configflow
raw = DataFrame(
    "time (d)" => 0:2,
    "mass (g)" => [1, 3, 7],
)

typed = unitfy(raw)
(names = names(typed), time = typed.time, mass = typed.mass)
```

`deunitfy(typed)` removes quantities and writes unit annotations back into
column names. Use it only at an output boundary that requires plain values;
keep quantities inside model calculations. A `provide` declaration performs
the same column-name interpretation by default through `autounit=true`.

## Avoid ambiguous combinations

- Use `config` for one scenario and `configs` for a collection. With `simulate`,
  both may be supplied deliberately: `config` becomes the shared base and each
  entry in `configs` is applied as a later patch.
- `evaluate` and `calibrate` instead treat `config` and `configs` as mutually
  exclusive. Merge a shared base into every entry before passing `configs` to
  those functions.
- Do not combine `configs` with the `simulate(parameters=...)` shortcut; those
  are alternative ways to generate scenario collections.
- Confirm that a target declaration has the `parameter` tag; otherwise a
  matching configuration entry cannot replace it.
- Check the system key, short variable name, and alias with `parameters` when a
  value appears to be ignored.
