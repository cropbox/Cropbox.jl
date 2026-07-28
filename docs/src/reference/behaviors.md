# [Behaviors and Tags](@id behaviors-and-tags)

This reference groups behaviors by modeling purpose and records the tags
accepted by the current implementation. It is intentionally about the DSL
features used by Cropbox models rather than every internal helper function.

## Choosing a behavior

Ask how the value changes:

- fixed after construction: `preserve`;
- recalculated from current dependencies: `track`;
- integrated through simulation time: `accumulate`;
- Boolean event or state: `flag`;
- read from indexed input: `provide` plus `drive`;
- generated child systems: `produce`;
- equation root: `solve` or `bisect`.

Use the smallest behavior that expresses the scientific meaning. A declaration
that happens to produce the same number with `preserve` and `track` still has a
different lifecycle and dependency contract.

## Core behaviors

### [`preserve`](@id behavior-preserve)

Initializes a value and normally does not update it again. Use it for constants,
parameters, initial conditions, and externally supplied objects.

Supported tags: `parameter`, `optional`, `override`, `extern`, `ref`, `min`,
`max`, `round`, `unit`.

```julia
coefficient => 0.8 ~ preserve(parameter, min = 0, max = 1)
```

`optional` changes the stored value type to allow `nothing`. With no body or
configured value, the value is `nothing`; an explicit configured `nothing` is
also retained. A configured `missing` instead means “use the declaration
default” and is not the spelling for an intentionally absent value.

### [`track`](@id behavior-track)

Recomputes the body in dependency order on every applicable update.

Supported tags: `override`, `extern`, `ref`, `skip`, `init`, `when`, `min`,
`max`, `round`, `unit`.

```julia
rate(T, Tb) => T - Tb ~ track(min = 0, u"K/d")
```

A self-dependency can express a discrete recurrence when an initial value is
explicit:

```julia
x(x) => 2x ~ track(init = 1)
```

Without `init`, the first evaluation has no `x` to read. This form is a
stepwise recurrence, not integration of a rate; use `accumulate` for a state
whose change is defined per unit time. Cycles between separate `track`
variables remain invalid.

With `when`, `track` stores the body only while the condition is true. When it
is false, the stored value is `init`, or zero when `init` is absent; it does
not retain the previous tracked value. Use `remember` for a one-time capture
that must then persist.

### [`accumulate`](@id behavior-accumulate)

Integrates a rate over model time. Its default update is an Euler-style
increment using the clock step or the time variable selected by tags.

Supported tags: `init`, `time`, `timeunit`, `reset`, `when`, `min`, `max`,
`unit`.

```julia
biomass(growth_rate) ~ accumulate(init = biomass0, u"g")
```

Without `init`, the stored state starts at zero in its declared type and unit.
The default `time` is `context.clock.time`; `timeunit` controls the rate unit
used for the elapsed interval. A true `when` condition enables the rate, while
`reset` schedules a return to `init` on the next update.

Several accumulated states may depend on one another, as in coupled
predator–prey equations. Cropbox advances their stored values before computing
the rates for the following interval, so each new rate sees the same updated
snapshot rather than a declaration-order-dependent partial update.

### [`flag`](@id behavior-flag)

Stores a Boolean condition. `once` makes a true event irreversible.

Supported tags: `parameter`, `override`, `extern`, `once`.

```julia
triggered(signal, threshold) => signal >= threshold ~ flag(once)
```

Use `once` only when the condition itself may later become false but the event
must remain recorded. A monotonic threshold such as accumulated thermal time
normally needs only `flag`.

### [`remember`](@id behavior-remember)

Keeps its `init` value until `when` first becomes true, captures the body at
that update, and then preserves the captured value.

Supported tags: `init`, `when`, `unit`.

```julia
maturity_date(date) ~ remember(when = mature)
```

Without `init`, the stored value starts at zero in the declared type and unit.
`when` should name the event that performs the one-time capture. After capture,
later changes in the body and condition do not change the remembered value.

## Time and numerical change

### [`advance`](@id behavior-advance)

Advances an internal sequence by a fixed step. Cropbox's clock uses this
behavior for time and tick counters. Without tags, `init` is zero and `step` is
one unit of the declared value.

Supported tags: `init`, `step`, `unit`.

The defaults are zero for `init` and one declared unit for `step`. The value
visible during an update is the pre-advance value; the internal next value is
then moved forward. Use `Clock` instead of declaring a second time base unless
the sequence has a genuinely different meaning.

### [`capture`](@id behavior-capture)

Stores the contribution over the most recent update interval: the previous
rate multiplied by elapsed `time`. The body establishes the rate for the next
interval. Unlike `accumulate`, it does not retain a running total.

Supported tags: `time`, `timeunit`, `when`, `unit`.

When its `when` condition is false, the rate stored for the following interval
is zero.

### [`integrate`](@id behavior-integrate)

Evaluates a numerical integral over a non-time argument during an update. It is
distinct from `accumulate`, which carries a state forward through simulation
time.

Supported tags: `from`, `to`, `unit`.

```julia
area(scale; x) => scale * sin(x) ~ integrate(from = 0, to = π)
```

Cropbox evaluates the integral with QuadGK's adaptive quadrature whenever the
variable updates. The single argument after `;` is the integration variable
and may carry its own type or unit, for example `x::Float64(u"m")`. `from` and
`to` provide its bounds.

## Tabular and functional data

### [`provide`](@id behavior-provide)

Normalizes an indexed table and makes it available to `drive` variables.

Supported tags: `parameter`, `index`, `init`, `step`, `autounit`.

```julia
data ~ provide(parameter, index = :date, init = calendar.date)
```

`init` identifies the first requested index value. `step` selects the required
index spacing. With `autounit=true`, compatible unit annotations in column names
are interpreted automatically.

The value may be a `DataFrame` or a CSV filename. Defaults are `index=:index`,
`init=context.clock.time`, `step=context.clock.step`, and `autounit=true`.
During construction Cropbox keeps rows on that exact index grid, then verifies
that the first row equals `init` and all retained gaps equal `step`. Missing
start rows and irregular coverage therefore fail early instead of silently
shifting weather or management data.

### [`drive`](@id behavior-drive)

Reads the current value from a provider.

Supported tags: `parameter`, `override`, `tick`, `from`, `by`, `unit`.

```julia
T: temperature ~ drive(from = data, by = :Tavg, u"°C")
```

`from` names a `provide` variable and `by` selects its column. When `by` is
omitted, the drive variable's short name is used. With no provider, the body or
a configured parameter may be a plain array:

```julia
fertilizer => [0, 20, 0, 0] ~ drive
```

The default `tick` is `context.clock.tick`; a custom integer-like tick may be
supplied for another sequence. A provider-backed drive cannot also have a body
or the `parameter` tag. Put configuration on the provider or use the direct
array form instead.

### [`tabulate`](@id behavior-tabulate)

Builds a named two-dimensional lookup table.

Supported tags: `parameter`, `rows`, `columns`, `unit`.

`rows` is required. If `columns` is omitted, the row names are reused for a
square table. Values can be read as `table.Row.Column`, `table[:Row][:Column]`,
converted to a `DataFrame`, or converted to a matrix. The configured matrix
shape must match the declared names.

### [`interpolate`](@id behavior-interpolate)

Builds an interpolation function from discrete pairs or a two-column table.
`reverse` constructs an inverse from another interpolation.

Supported tags: `parameter`, `reverse`, `knotunit`, `unit`.

Input may be key-value pairs or a two-column matrix. Knots are sorted and a
linear interpolation is constructed; `knotunit` belongs to inputs and `unit`
to outputs. `reverse` swaps the knots and values of another interpolation. The
mapping used for a reverse curve should be one-to-one over the supplied data.

### [`call`](@id behavior-call)

Builds a partial function whose dependencies are bound to the system and whose
arguments after `;` are supplied by the caller.

Supported tags: `unit`.

```julia
K(curve; θ) => curve(θ) ~ call(u"m/d")
```

The explicit argument can declare a static type and input unit, such as
`θ::Float64(u"rad")`. Those declarations become the callable signature.
Ordinary dependencies before `;` remain bound to the current system state.

## Dynamic structure and language extensions

### [`produce`](@id behavior-produce)

Creates and appends child systems during updates. The declaration usually calls
the exported `produce(SystemType)` helper in its body.

Supported tags: `single`, `when`.

Dynamic children make output, performance, and reproducibility more complex.
Always document production conditions and use `seed` when parameters are
stochastic.

The body may return one production request, several requests, or `nothing`.
`~ produce::Child` stores at most one child; a vector type such as
`~ produce::Child[]` appends children. Constructor keywords passed to
`produce(Child; ...)` are combined with the parent's shared context.
`single` is derived internally from this declared static type; model code
normally selects the behavior by writing `Child` or `Child[]`, not by adding a
`single` tag manually.
See [Dynamic Hierarchies](@ref dynamic-hierarchies) for the request helper,
hierarchy traversal, and simulation-output considerations.

### [`hold`](@id behavior-hold)

Declares a placeholder expected to be completed by another mixin. It accepts no
tags.

### [`wrap`](@id behavior-wrap)

Dependencies normally receive current values. `wrap(state)` passes the state
object itself:

```julia
@system WrappedState(Controller) begin
    source                => 1        ~ preserve
    doubled(wrap(source)) => 2source' ~ track
end
```

This makes storage identity and mutation visible to the equation. `wrap`
accepts no tags and should be rare in scientific model code. Use an ordinary
dependency whenever only the value is needed.

### [`bring`](@id behavior-bring)

Copies declarations from another system into the current system.

Supported tags: `parameters`, `override`.

`bring(parameters)` turns copied compatible declarations into configurable
parameters. Because this changes the public configuration surface, inspect the
result with `parameters` and `look`.

Unlike an ordinary typed child system, `bring` exposes the brought declarations
through its generated component and forwards their update stages. `override`
leaves construction to a parent declaration. Prefer mixins or an ordinary child
unless this forwarding behavior is specifically needed.

## Equation-solving behaviors

### [Residual equality with `⩵`](@id residual-equality)

Inside `solve` or `bisect`, `left ⩵ right` means the residual
`left - right`:

```julia
x    => (2x ⩵ 1)  ~ solve
y(y) => (y^2 ⩵ 2) ~ bisect(lower = 0, upper = 2)
```

It improves the readability of an equation but does not perform a Boolean
comparison. Use Julia's `==` when a Boolean result is intended.

### [`solve`](@id behavior-solve)

Solves a polynomial residual and selects a root.

Supported tags: `lower`, `upper`, `pick`, `unit`.

`lower` and `upper` filter real candidates; `pick` selects from those remaining
and defaults to `:maximum`. If no candidate lies inside the bounds, the current
implementation clips candidates to the nearest boundary instead of raising an
error. Check the residual and document the intended root rather than relying on
that fallback.

`solve` handles linear and quadratic expressions directly and uses polynomial
root finding for higher degrees. Complex roots are not returned. The expression
must be polynomial in the solved variable; use `bisect` for a bracketed
nonlinear response.

### [`bisect`](@id behavior-bisect)

Solves a nonlinear residual by bisection. The residual is written as a
self-referential declaration.

Supported tags: `lower`, `upper`, `maxiter`, `tol`, `min`, `max`, `evalunit`,
`unit`.

```julia
x(x) => x^2 - 2 ~ bisect(lower = 0, upper = 2, tol = 1e-8)
```

The residual must be bracketed by the lower and upper bounds. Distinguish the
solution `unit` from `evalunit`, which belongs to the residual.

If `lower` or `upper` is omitted, a corresponding `min` or `max` tag supplies
it. The same `min` and `max` tags are hard bounds while Cropbox attempts to
expand an initially invalid bracket. The defaults are `maxiter=150` and
`tol=1e-5`; specify them when numerical reproducibility across model versions is
important.

## Tag compatibility matrix

The table below mirrors the tags accepted by each behavior. A tag absent from a
row is rejected during `@system` expansion.

| Behavior | Supported tags |
|---|---|
| `preserve` | `parameter`, `optional`, `override`, `extern`, `ref`, `min`, `max`, `round`, `unit` |
| `track` | `override`, `extern`, `ref`, `skip`, `init`, `when`, `min`, `max`, `round`, `unit` |
| `flag` | `parameter`, `override`, `extern`, `once` |
| `remember` | `init`, `when`, `unit` |
| `accumulate` | `init`, `time`, `timeunit`, `reset`, `when`, `min`, `max`, `unit` |
| `capture` | `time`, `timeunit`, `when`, `unit` |
| `integrate` | `from`, `to`, `unit` |
| `advance` | `init`, `step`, `unit` |
| `provide` | `parameter`, `index`, `init`, `step`, `autounit` |
| `drive` | `parameter`, `override`, `tick`, `from`, `by`, `unit` |
| `tabulate` | `parameter`, `rows`, `columns`, `unit` |
| `interpolate` | `parameter`, `reverse`, `knotunit`, `unit` |
| `solve` | `lower`, `upper`, `pick`, `unit` |
| `bisect` | `lower`, `upper`, `maxiter`, `tol`, `min`, `max`, `evalunit`, `unit` |
| `produce` | `single` (inferred from type), `when` |
| `hold` | none |
| `wrap` | none |
| `call` | `unit` |
| `bring` | `parameters`, `override` |

## Cross-cutting tag semantics

### Configuration and construction

- `parameter`: allow configuration to provide the initial value.
- `extern`: accept a value supplied by a constructor or parent system.
- `override`: leave the declaration to construction or a compatible replacing
  declaration.
- `optional`: allow a preserved value to be `nothing`.
- `ref`: store a reference wrapper used for deliberate cross-component writes.

These tags affect ownership, not just numerical updates. Use them sparingly at
system boundaries and document who supplies the value.

### Initialization and conditions

- `init`: starting value or starting index, depending on the behavior.
- `when`: supply a Boolean condition whose effect depends on the behavior;
  `track` falls back to `init` or zero, cumulative behaviors use a zero rate,
  `remember` captures once, and `produce` gates child requests.
- `once`: prevent a `flag` from returning to false.
- `reset`: return an accumulator to its `init` value on the next update when
  the tag expression is true.
- `skip`: omit a tracked field from ordinary update traversal where the model
  coordinates it explicitly.

### Bounds and rounding

- `min`, `max`: clamp stored values.
- `round`: apply integer-style rounding; accepted values include `:round`,
  `:floor`, `:ceil`, and `:trunc`.
- `lower`, `upper`: solver search or root-selection bounds.
- `tol`, `maxiter`: iterative solver controls.

Bounds can prevent invalid output but can also hide an invalid equation. Explain
scientific bounds in the variable docstring and test behavior at the boundary.

### Time

- `time`: select the time variable used by a cumulative behavior.
- `timeunit`: interpret a rate relative to a chosen unit.
- `step`: advance or table index spacing.
- `tick`: select the data-row tick used by `drive`.

Do not compensate for a wrong `Clock.step` by changing rate units. Verify the
model time scale, rate dimension, and snapshot frequency separately.

## Full examples

Use [DSL Syntax](@ref dsl-syntax) for complete declaration grammar and the
[weather-driven model](@ref phenology-tutorial) for an executable example that
combines parameters, tabular input, conditional state, and accumulation.
