# [System](@id system)

A Cropbox system is a reusable model component. It groups variables and their
dependencies into one specification, from a small temperature response to an
entire crop model. `@system` analyzes that specification and creates a Julia
system type; `instance` constructs a particular initialized model from the type.

This distinction is important: declaring a system does not run it, and changing
a configuration does not rewrite its equations.

## [Creating a System](@id Creating-a-System)

```@example systemguide
using Cropbox

@system GrowthProcess begin
    rate: growth_rate => 1.5 ~ preserve(parameter, u"g/hr")
    mass(rate)               ~ accumulate(u"g")
end

@system GrowthModel(GrowthProcess, Controller)
```

`GrowthProcess` is reusable and has no root controller of its own.
`GrowthModel` composes that process with `Controller`, making it suitable for
`instance`, `simulate`, and `visualize`.

Use [DSL Syntax](@ref dsl-syntax) for the complete header and variable grammar.
Use `look(GrowthModel)` to inspect the composed declaration.

## [Mixin](@id Mixin)

Systems named in parentheses are mixins:

```julia
@system Model(Weather, Phenology, Growth, Controller)
```

Cropbox merges their declarations from left to right. When two mixins declare
the same public variable, the later declaration takes precedence; a declaration
in the new system block can then complete or replace the merged result. Because
composition order is meaningful, inspect the final system with `look(Model)`
instead of assuming that every source declaration remains unchanged.

Keep process components small enough to test independently. Add `Controller`
only to the root system that will be constructed directly.

## Child systems

A system may also contain another system as a typed variable. This pattern is
useful when the child should remain a distinct namespace rather than have all of
its variables mixed into the parent.

```julia
@system DatedProcess begin
    calendar(context)   ~ ::Calendar
    date(calendar.date) ~ track::date
end
```

The child receives the parent's context, so configuration and time remain
consistent. Its values can be addressed with paths such as `"calendar.date"`.
Use mixins when declarations should become part of one public surface; use a
child system when the component should keep its own path and identity.

## [Context](@id Context)

Every constructed Cropbox system receives a `Context`. The context carries the
normalized configuration and the simulation `Clock`, allowing composed systems
to share one time base and one configuration tree.

For ordinary modeling, treat context as framework infrastructure. Access values
through paths such as `context.clock.time`, and configure the public systems
rather than mutating context fields.

### [Config](@id Config)

A `Config` maps system and variable names to values. It is an input object, not
a model system. Prefer `@config` for constructing and combining configurations,
and prefer system types as keys when they are available so names and units can
be checked early.

## [Controller](@id Controller)

`Controller` creates the root context. A reusable component normally omits it;
an executable root normally includes it once.

```@example systemguide
s = instance(GrowthModel;
    config = GrowthProcess => :rate => 2u"g/hr",
)

(rate = s.rate', mass = s.mass')
```

If construction reports that a context or configuration source is missing,
check that the system passed to `instance` or `simulate` ultimately includes
`Controller`. Do not add a separate controller to every nested component.

## [Clock](@id Clock)

`Clock` tracks elapsed model time and update count. Configure its step like any
other system parameter:

```@example systemguide
config = @config (
    GrowthProcess => :rate => 2u"g/hr",
    Clock => :step => 30u"minute",
)

result = simulate(GrowthModel;
    config,
    stop = 2u"hr",
    target = :mass,
)
```

`Clock.step` controls model updates. The `snap` option controls only which
updated states become output rows. Keep those two decisions separate when
checking numerical accuracy or performance.

## [Calendar](@id Calendar)

`Calendar` maps elapsed clock time to a `ZonedDateTime` and date. It is not
automatically added to every system; declare or mix in a component that uses it,
then configure its initial time.

```julia
using TimeZones

config = @config (
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 4, 1, tz"UTC"),
)
```

Use a calendar when the model depends on dates, time zones, or indexed weather
data. Use the plain clock when elapsed model time is sufficient.

## Inspect and construct

- `look(SystemType)` shows the composed declarations;
- `parameters(SystemType)` lists configurable inputs;
- `instance(SystemType; config)` constructs and initializes one model;
- `simulate(SystemType; ...)` constructs a fresh model, advances it, and returns
  tabular output.

Continue with [Systems and Simulation Lifecycle](@ref simulation-lifecycle) for
construction and update timing, or [Configure Models and Scenarios](@ref
configuration-workflow) for configuration patterns.
