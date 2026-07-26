# [Values, Units, and Structure](@id utility-api)

Most Cropbox models need only `@system`, `@config`, `simulate`, and
`visualize`. The functions on this page become useful when Julia code crosses
the boundary between a Cropbox state and an ordinary value, when data enters or
leaves a unit-aware model, or when a model contains a changing hierarchy.

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
- a Cropbox plot returns its backend plot object;
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
replacement for `update!`: cumulative, event, and solver behaviors have
lifecycle rules that a body-only evaluation cannot reproduce.

## Remove a dependency's unit with `nounit`

Inside a declaration, Cropbox normally unwraps a dependency to its unit-aware
value. `nounit(state)` instead passes its plain numerical magnitude:

```julia
@system UnitBoundary(Controller) begin
    length                         => 1          ~ preserve(u"m")
    length_number(nounit(length))                  ~ track
    length_cm(nounit(length, u"cm"))               ~ track
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

## Update an instance with `update!`

```julia
update!(instance)
```

One call performs one generated Cropbox update cycle in dependency order. It
is useful in tests and tightly controlled interactive code:

```julia
s = instance(Model; config)
update!(s)
value(s.context.clock.time)
```

For normal runs, prefer `simulate` or `simulate!`; they also handle stopping,
snapshots, callbacks, output selection, and progress. Do not manually update an
instance while a simulation callback is traversing the same instance.

`update!` is also an internal extension point with stage arguments, and Cropbox
uses the same exported name for updating a plot's option store. Those methods
are implementation-facing; model code should normally call the one-argument
system form or the documented `plot!`/`visualize!` functions.

## Stochastic configuration with `±`

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
are needed. The CropRootBox tutorial shows this pattern in a dynamic root model.

## Equation equality with `⩵`

Inside `solve` or `bisect`, `left ⩵ right` means the residual
`left - right`:

```julia
x => (2x ⩵ 1) ~ solve
y(y) => (y^2 ⩵ 2) ~ bisect(lower = 0, upper = 2)
```

It improves the readability of an equation but does not perform a Boolean
comparison. Use Julia's `==` when a Boolean result is intended.

## Pass a state object with `wrap`

Dependencies normally receive current values. `wrap(state)` passes the state
object itself:

```julia
@system WrappedState(Controller) begin
    source              => 1       ~ preserve
    doubled(wrap(source)) => 2source' ~ track
end
```

This makes storage identity and mutation visible to the equation, so it should
be rare in scientific model code. Use an ordinary dependency whenever only the
value is needed. See [`wrap`](@ref behavior-wrap) for its behavior role.

## Create child systems with `produce`

The helper and the behavior have the same name but different jobs:

```julia
produce(ChildSystem; constructor_keywords...)  # production request
children => produce(ChildSystem) ~ produce      # declaration behavior
```

The helper makes a request. During the following production stage, Cropbox
constructs the child with the parent's context and any supplied keywords. A
vector-typed production appends children; a single-system production creates
at most one child. `produce(nothing)` makes no request, which is useful for a
conditional body. The `when` tag is the clearer choice when production depends
on a Cropbox flag.

Produced children are updated as part of the parent hierarchy. Their number and
shape can change during a run, so ordinary scalar simulation output cannot
store the whole structure. Summarize it with `snatch`, or traverse it at chosen
snapshots with `gather!`.

## Traverse a hierarchy with `Gather`

```julia
gather!(root, TargetSystemTypes...;
    store = [],
    callback = visit!,
    kwargs = (),
)

Gather(TargetSystemTypes, store, callback)
gather!(gather, value; keyword_context...)
visit!(gather, value; keyword_context...)
```

`visit!` recursively follows system fields and vectors of systems. `gather!`
dispatches the callback with `(gather, value, Val(:MatchedType))`; unmatched
values receive `Val(nothing)`. A collecting callback usually has one matching
method and one fallback:

```julia
function collect_roots!(g::Gather, root::BaseRoot, ::Val{:BaseRoot})
    push!(g, root)
    visit!(g, root)
end

collect_roots!(g::Gather, value, _) = visit!(g, value)

roots = gather!(architecture, BaseRoot;
    callback = collect_roots!,
)
```

The fallback is important because it continues walking through containers that
do not themselves match the requested type. After collection, `value(g)`,
`g[]`, and `g'` return the underlying store. `push!` and `append!` on the
`Gather` forward to that store, so it may be a vector or another compatible
accumulator.

The default callback traverses but does not decide what to collect. Model
packages such as CropRootBox therefore provide their own callbacks. Reuse a
`Gather` object when several traversals should append into one store; create a
new one for independent summaries.

## Where these APIs appear

| Need | API | Worked example |
|---|---|---|
| read a model field | `value` or `'` | Quick Start and inspection workflow |
| exchange CSV data with units | `unitfy`, `deunitfy` | configuration workflow and built-in stores |
| stochastic structure | `±`, `seed` | CropRootBox tutorial |
| dynamic child systems | `produce` | behavior reference and CropRootBox |
| summarize a hierarchy | `Gather`, `gather!`, `visit!` | CropRootBox tutorial |
| inspect a state-dependent formula | `value(system, :name, ...)` | advanced debugging only |
