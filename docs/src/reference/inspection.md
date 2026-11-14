# [Inspection](@id Inspection1)

Inspection functions answer different questions about one model:

| Function | Question |
|---|---|
| `parameters` | What may configuration change, and what are the current/default values? |
| `look` | What does this system or variable declare? |
| `@look` | Can I write the same inspection in convenient property syntax? |
| `dive` | What is inside this constructed nested instance? |
| `visualize` | How do variables depend on one another, and how are systems composed? |

Use the type when studying structure and an instance when current values
matter.

## `parameters`

```julia
parameters(SystemType;
    alias = false,
    recursive = false,
    exclude = (),
    scope = nothing,
)

parameters(instance;
    alias = false,
    recursive = false,
    exclude = (),
)
```

- `alias=true` uses a descriptive alias when one exists.
- `recursive=true` follows declared child systems and includes their
  parameters.
- `exclude=(Context,)` or another type tuple omits infrastructure or a branch
  that should not be followed.
- `scope` selects the module in which type defaults and constants are
  evaluated. Its default is the module where the system was declared.

The type form can evaluate only a parameter default with no model-variable
dependencies. It reports a dependent or externally required default as
`missing`. The instance form reads current values, so it is the better choice
after configuration has been applied.

`recursive=true` follows types visible in declarations. A dynamically typed
vector of systems may not reveal every runtime child type; inspect a constructed
instance or use a model-specific hierarchy traversal in that case.

## Inspect declarations with `look`

```julia
look(SystemType)
look(instance)
look(SystemType, :variable)
look(instance, :variable)
look(Module, :SystemName)
```

For a system, `look` shows the system docstring and public declaration surface.
For a variable, it shows the variable docstring and normalized declaration
line. Supplying an instance also shows current values.

The display sections can be selected with keywords:

| Keyword | Applies to | Default | Meaning |
|---|---|---:|---|
| `header` | all forms | `true` | show section labels such as `[doc]` |
| `doc` | system or variable | `true` | show stored documentation |
| `system` | system summary | `true` | show fields and current values when available |
| `code` | variable on a type | `true` | show the declaration line |
| `value` | variable on an instance | `true` | show the current value |
| `excerpt` | variable documentation | `false` | show only its first documentation line |

These switches are useful when embedding inspection output in a notebook, but
they do not change the model. A declaration printed by `look` is the composed
result, which may differ from the source line in an earlier mixin.

## Use property syntax with `@look`

The macro supplies convenient property-like spelling:

```julia
@look Model
@look Model.variable
@look instance.variable
@look Model variable
```

The dotted forms with no call are equivalent to `look(Model, :variable)`.

A dotted call is intentionally different:

```julia
@look instance.response(25u"°C")
@look instance.response(; temperature = 25u"°C")
```

It calls `value(instance, :response, ...)` to evaluate a function-like
declaration body. It does not print declaration documentation. Use
`look(instance, :response)` when inspection, rather than evaluation, is the
goal.

## `dive`

```julia
dive(instance)
```

`dive` opens a terminal menu for walking through nested systems, state values,
and vectors of systems. Use the arrow keys to select an item, Enter to descend,
and `q` to move back. A leaf first displays `look`; pressing Enter again returns
that object to the REPL.

The menu needs a real terminal. In an initialized IJulia session, `dive`
falls back to the noninteractive `look(instance)` summary. In notebooks and
scripts, explicit property paths and `look` are easier to reproduce.

## [Model structure](@id visualization-structure)

With only a system type, `visualize` returns a structural graph instead of
simulating a trajectory. The default `kind = :dependency` shows variables and
their generated update stages. `kind = :hierarchy` shows system composition and
mixins, omitting nested `Context` infrastructure. A dependency graph covers the
composed declarations of one system, including mixins; child systems are not
recursively expanded into their variables.

| Question | Call |
|:---|:---|
| What are the declared dependencies? | `visualize(S)` |
| Which systems and mixins compose the model? | `visualize(S; kind = :hierarchy)` |
| What directly supplies `x`? | `visualize(S, :x; direction = :up)` |
| What directly uses `x`? | `visualize(S, :x; direction = :down)` |
| What connects `a` to `c`? | `visualize(S, :a => :c)` |

For name selectors, the defaults are `depth = 1` and `direction = :both`.
`depth` counts variable boundaries, not the generated phases of one variable.

```@example structure
using Cropbox

@system Supply begin
    rate => 2 ~ preserve(parameter, u"g/hr")
end

@system StructuralGrowth(Controller) begin
    supply(context)            ~ ::Supply
    gain(r = supply.rate) => r ~ track(u"g/hr")
    mass(gain)                 ~ accumulate(u"g")
end

visualize(StructuralGrowth)
```

```@example structure
visualize(StructuralGrowth; kind = :hierarchy)
```

These graphs describe declared relationships, not observed activity in a run.
`visualize(S, x, y; kind = :line, stop = ...)` still means a simulation plot;
`visualize(df, x, y)` uses saved data. Variable selectors are supported only for
`kind = :dependency`. `visualize!` remains a plot-layer operation, not a way to
modify a structural graph.

### A built-in thermal response

No scenario or input data are needed to inspect the built-in growing-degree
response, even though its temperature parameters normally come from configuration:

```@example structure
visualize(GrowingDegree)
```

The arrows run from a dependency to its consumer. `T` and the temperature
thresholds determine `ΔT`; `ΔT` and `Δt` determine the rate `r`. This component
computes a rate, not a cumulative thermal-time total. The
[phenology tutorial](@ref phenology-tutorial) shows a weather-driven model with
an accumulating state.

At `depth = 0`, only selected variables and their configuration source remain:

```@example structure
visualize(GrowingDegree, [:Tb, :To, :Tx]; depth = 0)
```

The dotted arrows point **from `config` to the parameters**, not the reverse.
An alias such as `:base_temperature` can select `Tb`; `style = (alias = true,)`
at export time changes the displayed labels to the declared aliases. Labels
are taken from declarations, not generated descriptions.

### Select neighborhoods or paths

```@example structure
@system PathDemo begin
    a: input => 1     ~ preserve(parameter)
    b(a)     => 2a    ~ track
    c(b)     => b + 1 ~ track
    d(c)     => 2c    ~ track
    e(d)     => d + 1 ~ track
    side(a)  => -a    ~ track
end

visualize(PathDemo, [:a, :e])
```

A name or list of names selects their neighborhoods. Here `depth = 1` includes
the side branch and the neighbors of both endpoints, but does not reach `c`.
`depth = 0` keeps only the selected variables. `direction = :up` follows inputs,
`:down` follows affected variables, and `:both` follows both directions.

Compare the two directions around the same variable:

```@example structure
visualize(PathDemo, :b; direction = :up)
```

```@example structure
visualize(PathDemo, :b; direction = :down)
```

The first keeps `a → b` (and the configuration source for `a`); the second
keeps `b → c`. Increasing `depth` adds another variable boundary in the chosen
direction. It does not rank variables by importance.

```@example structure
visualize(PathDemo, :a => :e)
```

A pair selects every directed path between its endpoints: this includes `c`
but excludes `side`. Paths are not limited by `depth` or `direction`. For a
short chain, a neighborhood selection and a path can happen to look identical.

```@example structure
visualize(PathDemo, [:side, :a => :e]; depth = 0)
```

A mixed vector combines neighborhoods and paths. An endpoint can itself be a
vector, such as `[:a, :b] => [:d, :e]`; a vector of pairs selects independent
paths without adding cross-pair paths. Vector endpoints include all existing
source-to-target combinations. Aliases are accepted as selectors.
Unknown variables, empty selections, and pairs with no directed path are errors.
Included variables retain all their generated phases, and parameters retain
their configuration source, even at `depth = 0`.

Selections show only edges already present between retained nodes. They do not
invent a shortcut edge over an omitted intermediate variable. A path selection
also does not include every input to its intermediate variables: use an
upstream neighborhood or the full graph to inspect those additional inputs.
Paths follow generated update stages; they do not cross from a state's
post-update stage to its main stage in the next timestep. For relationships
across that boundary, combine paths and neighborhoods as in the
[phenology example](@ref phenology-tutorial).

### Read the symbols

| Appearance | Meaning |
|:---|:---|
| Plain label | Ordinary derived or fixed variable, remembered value, or system reference |
| Rectangle | Accumulating state (`accumulate`, `capture`, `integrate`, `advance`) |
| Double rounded rectangle | Produced systems |
| Parallelogram / cylinder | Driver / provided storage |
| Diamond / hexagon | Condition / solver |
| Italic label | Language-level declaration (`hold`, `wrap`, `call`, `bring`) |
| Bold label | Selected variable or path endpoint; hierarchy labels are also bold |
| `∘name` / `⋆name` | Preparation / post-update phase of one variable |
| Dashed node outline | Preparation stage of a shaped node |
| Solid arrow | Ordinary dependency |
| Dotted arrow with open box head | Configuration input to a parameter |
| Open triangle head / small vee | Preparation dependency / connection between phases of one variable |

Hierarchy arrows point from a child system or mixin to the containing or
derived system. Dashed hierarchy edges denote mixins. Shape and line style
carry the distinctions without requiring colors, unit labels, or state names.

The prefixes `∘` and `⋆` distinguish generated preparation and post-update
stages of the **same variable**. They do not mean two independent variables or
the next simulation timestep. A phase connection is solid with a small vee
head; a dashed node outline marks preparation, while a dotted edge marks a
configuration input. See [Model Execution](@ref model-execution) for the update
lifecycle and [Behaviors and Tags](@ref behaviors-and-tags) for each state's semantics.

For example, a bisection solver has preparation and main stages:

```@example structure
@system RootStages begin
    target => 2 ~ preserve(parameter)
    lower  => 0 ~ preserve(parameter)
    upper  => 2 ~ preserve(parameter)

    root(root, target) => root^2 - target ~ bisect(lower = lower, upper = upper)
end

visualize(RootStages)
```

Bounds feed the preparation stage `∘root`; `target` feeds the equation at
`root`. The graph does not expand the solver's internal iterations.

Produced systems use the same phase notation with double rounded rectangles:

```@example structure
@system LeafUnit begin
    area => 1 ~ preserve(u"cm^2")
end

@system CanopyStages(Controller) begin
    leaves => produce(LeafUnit) ~ produce::LeafUnit[]
end

visualize(CanopyStages, :leaves; depth = 0)
```

This is a declaration graph, not a count of leaves created during a run.
`visualize(CanopyStages; kind = :hierarchy)` follows the declared child type;
`visualize(LeafUnit)` inspects that child's variables. Use the
[dynamic hierarchy APIs](@ref dynamic-hierarchies) to inspect runtime children.

### Display, grouping, and export

Structural graphs use bundled Graphviz, not the Makie/UnicodePlots plotting
backends. Notebooks display SVG; terminals show a compact text summary without
running Graphviz. A failed automatic SVG render shows a fallback notice;
explicit image export reports the rendering error.

```@example structure
g = visualize(StructuralGrowth)
Cropbox.writeimage("structure.svg", g; style = (group = :system,))
Cropbox.writeimage("structure.pdf", g)
Cropbox.writedot("structure.dot", g)
nothing # hide
```

Download the [grouped SVG](structure.svg), [PDF](structure.pdf), or
[Graphviz source](structure.dot). `group = :system` clusters variables by their
declaring system or mixin; it does not expand child-system instances.

Rendering options belong to `style` in `writeimage` or `writedot`, leaving the
graph unchanged. Supported keys are `alias`, `group`, `rankdir`, `ratio`,
`ranksep`, `nodesep`, `splines`, `fontname`, `fontsize`, `margin`, `arrowsize`,
and `penwidth`; `alias` and `group` apply only to dependency graphs. For example,
`style = (rankdir = :LR, group = :system)` gives a left-to-right grouped graph.
`writeimage` also accepts `engine = :neato` or another Graphviz layout engine;
the default is `:dot`. `writedot` does not require a working renderer.

To explicitly use the terminal fallback, call
`show(stdout, MIME("text/plain"), g)`. Dependency text lists a valid generated
update order, not a measured execution trace. If image rendering fails, save
DOT with `Cropbox.writedot("structure.dot", g)`; an explicit `writeimage` call
reports the Graphviz error rather than silently succeeding. Bold and italic
labels retain the chosen font family. Fonts are resolved by the rendering
environment, so a custom `fontname` is not bundled with an export.

### Scope and larger models

- These are static declaration graphs. They do not show runtime values,
  configuration-specific active branches, elapsed time, or sensitivity.
- Dependencies include declared arguments and tags, not only equation bodies.
  A scientific feedback may span state-update phases rather than form a cycle
  in the generated scheduling graph.
- A nested reference such as `supply.rate` is represented through `supply` in
  the parent graph. Inspect `Supply` separately for its internal variables;
  dotted cross-system paths are not selectors in this interface.
- Hierarchies follow declared system types, not every runtime instance of
  that type. A dynamically chosen child type may not be discoverable statically.
- Grouping changes presentation, not selection. There is no automatic
  importance filter or recursive variable flattening in this interface.

For larger models, start with the hierarchy, then select an output's upstream
neighborhood and increase `depth` as needed. The
[SimpleCrop example](@ref simplecrop-tutorial) demonstrates this workflow;
the [phenology example](@ref phenology-tutorial) groups a weather-to-state path
by its declaring systems.

The underlying `Cropbox.dependency` and `Cropbox.hierarchy` helpers remain
unexported implementation utilities. Their graph fields are not a stable
serialization format; use `visualize` as the model-facing entry point.
