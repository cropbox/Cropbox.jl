# [Values and Units](@id utility-api)

Most Cropbox models need only `@system`, `@config`, `simulate`, and
`visualize`. The functions on this page become useful when Julia code crosses
the boundary between a Cropbox state and an ordinary value, when data enters or
leaves a unit-aware model.

## Read current values with `value`

A field of a system is usually a Cropbox state object. Read its stored value
with either postfix `'` or `value`:

```julia
s.mass'
value(s.mass)
```

`value(x)` has these public conveniences:

- a Cropbox state returns its current stored value;
- a vector of states returns a vector of their values;
- an ordinary value is returned unchanged;
- a Cropbox `Plot` wrapper returns its backend object;
- a `Gather` returns its store.

Postfix `'` is concise in the REPL. `value` is easier to read in functions,
callbacks, and teaching material. Reading a value does not update the model.

There is also an inspection-oriented call form:

```julia
value(instance, :variable, explicit_arguments...; dependency_overrides...)
value(SystemType, :variable, explicit_arguments...; dependency_values...)
```

It evaluates the declaration body without storing the result. This is intended
for checking `preserve`, `track`, and `call` equations. It is not a general
replacement for [`update!`](@ref manual-update): cumulative, event, and solver
behaviors have lifecycle rules that a body-only evaluation cannot reproduce.

## Remove a dependency's unit with `nounit`

Inside a declaration, Cropbox normally unwraps a dependency to its unit-aware
value. `nounit(state)` instead passes its plain numerical magnitude:

```julia
@system UnitBoundary(Controller) begin
    length => 1                      ~ preserve(u"m")
    length_number(nounit(length))    ~ track
    length_cm(nounit(length, u"cm")) ~ track
end
```

The first numerical result is `1`; the second is `100`. Supplying a unit first
converts to that unit and then removes it.

Use `nounit` at a deliberate boundary to code that cannot accept Unitful
quantities. Keep units through the rest of the model so dimensional errors are
still detected. The output option `simulate(...; nounit=true)` is different: it
strips units only after the simulation has finished.

## Convert values with `unitfy` and `deunitfy`

```julia
unitfy(value, unit)
deunitfy(value)
deunitfy(value, unit)
```

`unitfy` attaches a unit to a plain value or converts an existing compatible
quantity. `deunitfy(value)` removes units without changing the displayed
magnitude. `deunitfy(value, unit)` converts first and then removes the unit.

```@example utilityref
using Cropbox

(
    attached = unitfy(2, u"m"),
    converted = unitfy(2u"m", u"cm"),
    stripped = deunitfy(2u"m"),
    stripped_cm = deunitfy(2u"m", u"cm"),
)
```

Scalars, arrays, tuples, and ranges are supported. `nothing` and `missing` are
preserved. Incompatible dimensions raise a Unitful error rather than being
silently reinterpreted. Temperature ranges are handled as affine units, so use
`unitfy` instead of multiplying a numeric range by an offset unit.

### DataFrame round trips

`deunitfy(df)` strips each unit-aware column and records its unit in the column
name. `unitfy(df)` reads those suffixes back:

```@example utilityref
using DataFrames

df = DataFrame(time = (0:2)u"d", mass = [0, 2, 5]u"g")
plain = deunitfy(df)
restored = unitfy(plain)

(plain = plain, restored = restored)
```

A suffix such as `"mass (g)"` is read as a unit. A suffix beginning with a
colon, such as `"date (:Date)"`, is read as a type constructor instead. `Date`
has a built-in mapping; other constructors must be available in the evaluation
scope or supplied as keywords to `unitfy`.

This convention is used by the built-in CSV stores. Treat column names as a
file-format contract: changing or removing the final parenthesized suffix
changes how the data is parsed.

## Where these APIs appear

| Need | API | Worked example |
|---|---|---|
| read a model field | `value` or `'` | Quick Start and inspection workflow |
| exchange CSV data with units | `unitfy`, `deunitfy` | configuration workflow and built-in stores |
| inspect a state-dependent formula | `value(system, :name, ...)` | advanced debugging only |

Manual updates are covered by [Simulation](@ref Simulation1). Stochastic
parameter values are covered by [Configure Models and Scenarios](@ref
stochastic-configuration). For `⩵` and `wrap`, see [Behaviors and Tags](@ref
behaviors-and-tags). Dynamic child systems and traversal are documented in
[Dynamic Hierarchies](@ref dynamic-hierarchies).
