# [Systems and Composition](@id system)

A Cropbox system groups variables and their dependencies into a reusable model
component. Here we separate the growth process from the executable model used
in the Quick Start. `@system` creates a Julia system type; `instance` constructs
a particular initialized model from that type.

This distinction is important: declaring a system does not run it, and changing
a configuration does not rewrite its equations.

## [Create a system](@id Creating-a-System)

```@example systemguide
using Cropbox

@system GrowthProcess begin
    r: growth_rate       => 0.05                 ~ preserve(parameter, u"d^-1")
    Wf: final_biomass    => 300                  ~ preserve(parameter, u"g")
    W0: initial_biomass  => 0.25                 ~ preserve(parameter, u"g")

    W(W, r, Wf): biomass => r * W * (1 - W / Wf) ~ accumulate(init = W0, u"g")
end

@system LogisticGrowth(GrowthProcess, Controller)
```

`GrowthProcess` is reusable and has no root controller of its own.
`LogisticGrowth` composes that process with `Controller`, making it suitable for
`instance`, `simulate`, and `visualize`.

Use [DSL Syntax](@ref dsl-syntax) for the complete header and variable grammar.
Use `look(LogisticGrowth)` to inspect the composed declaration.

## [Compose systems with mixins](@id Mixin)

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

## Keep child systems separate

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

## [Add a controller](@id Controller)

A reusable process normally omits `Controller`. The system passed directly to
`instance`, `simulate`, or `visualize` normally includes it once. `Controller`
creates the shared runtime context and configuration used by the composed
model.

An instance field such as `s.r` is a Cropbox state, not a bare number. Postfix
`'` reads its current value, including units: `s.r'` is equivalent to
`value(s.r)`. Reading a value does not advance the model. See
[Values and Units](@ref utility-api) for the full reference.

```@example systemguide
s = instance(LogisticGrowth;
    config = GrowthProcess => :r => 0.07,
)

@show s.r'
@show s.W'
nothing # hide
```

If construction reports that a context or configuration source is missing,
check that the system passed to `instance` or `simulate` ultimately includes
`Controller`. Do not add a separate controller to every nested component.

## Inspect and construct

- `look(SystemType)` shows the composed declarations;
- `parameters(SystemType)` lists configurable inputs;
- `instance(SystemType; config)` constructs and initializes one model.

Continue with [Model Execution](@ref model-execution) for configuration,
context, time, construction, updates, and simulation. Use
[DSL Syntax](@ref dsl-syntax) when you need the full declaration grammar.
