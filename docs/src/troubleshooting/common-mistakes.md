# [Common Mistakes](@id common-mistakes)

These errors occur repeatedly when moving from a small equation to a composed
model. The examples focus on recognizing the mistake rather than memorizing an
error message.

## Forgetting a root `Controller`

```julia
@system Process begin
    x => 1 ~ preserve
end

instance(Process)  # no root context/configuration source
```

Keep reusable process systems controller-free, then compose an executable root:

```julia
@system Model(Process, Controller)
```

Nested systems should receive the parent's context rather than creating another
controller.

## Using the wrong behavior

```julia
biomass(rate) ~ track       # current rate, not accumulated biomass
parameter => 1 ~ track      # recalculated even though conceptually fixed
```

Use `preserve` for fixed inputs, `track` for current algebraic values, and
`accumulate` for state integrated through time. Choose based on lifecycle, not
on the value returned in one snapshot.

## Hiding a unit error with a plain number

```julia
config = Clock => :step => 1  # one default clock unit, not necessarily one day
```

Write `1u"d"` when a day is intended. At model boundaries, explicit quantities
make configuration portable across clocks and packages.

## Treating Celsius differences as Celsius values

An absolute temperature may use `u"°C"`; a difference uses kelvin. Thermal time
is usually `K*d`, not `°C*d`. Let Unitful expose incorrect equations instead of
removing units early.

## Declaring a parameter without `parameter`

```julia
rate => 1 ~ preserve
```

This is a constant. Configuration can replace only a compatible declaration
tagged `parameter`:

```julia
rate => 1 ~ preserve(parameter)
```

## Configuring the alias or wrong system blindly

Large models reuse names such as `T`, `rate`, or `init`. Inspect the parameter
surface before writing a patch and verify the resulting instance afterward.
Remember that later configuration fragments override earlier ones.

## Confusing dependencies with function arguments

Before `;`, entries are model dependencies. After `;`, entries are explicit
arguments for function-like behaviors.

```julia
f(scale; x) => scale * x ~ call
```

Here `scale` comes from the model and `x` is supplied when `f(x)` is called.

## Creating an ordinary dependency cycle

```julia
a(b) => b + 1 ~ track
b(a) => a + 1 ~ track
```

There is no valid update order. Reformulate the model using an explicit state,
lag, accumulator, or solver. Do not break the cycle by arbitrarily removing a
scientific dependency.

## Expecting `snap` to change the time step

`Clock.step` controls updates; `snap` controls output. Saving daily from an
hourly model still performs 24 hourly updates per day. Conversely, a daily clock
cannot recover an hourly event by using `snap=1u"hr"`.

## Reusing a mutated instance as a replicate

`simulate!` continues an instance. Construct a fresh instance for each replicate
or scenario. This is especially important for accumulated states and dynamic
structures.

## Collecting every variable by default

Default output is convenient during exploration but costly and fragile in a
large model. Provide a stable `target` list, use nested paths intentionally, and
increase `snap` intervals before a production run.

## Expecting `target` to serialize a complex object

Output extraction is tabular: it keeps scalar numbers, symbols, strings, and
date/time values. Naming a vector, dictionary, tuple, mesh, or dynamic system in
`target` does not make it a DataFrame column. Add scalar summary declarations or
use `snatch` when output depends on the complete object.

## Using wildcards in final analyses

`"*"` and `"child.*"` change when model fields change. They are discovery tools,
not a durable data schema. Replace them with named pairs and explicit columns.

## Mutating a shared configuration input

A DataFrame or external object in configuration may be shared by multiple
scenarios. Use `copy` before changing a treatment input, and avoid sharing
mutable constructor options across threaded simulations.

## Ignoring data coverage and time zones

A correct equation still fails when weather ends before the model, dates are
duplicated, or `Calendar` uses another zone. Validate index type, order,
uniqueness, coverage, and time zone before calibrating anything.

## Increasing solver iterations before checking the bracket

`maxiter` controls work after a valid problem is defined. For `bisect`, evaluate
the residual at `lower` and `upper` first. For `fixedpoint`, inspect the update
map, initial value, damping, and clipping.

## Calibrating too much at once

Large parameter sets can compensate for structural errors and produce weakly
identified fits. Begin with process diagnosis, defensible bounds, one target,
and a small optimizer budget. Validate on held-out environments.

## Timing compilation instead of simulation

The first call includes Julia compilation. Warm up a representative small case,
then measure the section relevant to the scientific workload. Do not claim a
solver or DSL optimization from one cold run.
