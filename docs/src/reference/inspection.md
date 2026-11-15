# [Inspection](@id Inspection1)

Inspection functions answer different questions about one model:

| Function | Question |
|---|---|
| `parameters` | What may configuration change, and what are the current/default values? |
| `look` | What does this system or variable declare? |
| `@look` | Can I write the same inspection in convenient property syntax? |
| `dive` | What is inside this constructed nested instance? |
| `visualize` | How are variables/systems related, and in what order are they updated? |

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

- `alias = true` uses a descriptive alias when one exists.
- `recursive = true` follows declared child systems and includes their
  parameters.
- `exclude = (Context,)` or another type tuple omits infrastructure or a branch
  that should not be followed.
- `scope` selects the module in which type defaults and constants are
  evaluated. Its default is the module where the system was declared.

The type form can evaluate only a parameter default with no model-variable
dependencies. It reports a dependent or externally required default as
`missing`. The instance form reads current values, so it is the better choice
after configuration has been applied.

`recursive = true` follows types visible in declarations. A dynamically typed
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

With only a system type, `visualize` returns a static diagram instead of
simulating a trajectory. The default `kind = :dependency` shows variables and
their generated update stages. `kind = :hierarchy` shows system composition and
mixins, omitting nested `Context` infrastructure. A dependency graph covers the
composed declarations of one system, including mixins; child systems are not
recursively expanded into their variables. `kind = :flow` arranges one
system's update operations vertically, with a lane for each variable.

| Question | Call |
|:---|:---|
| What are the declared dependencies? | `visualize(S)` |
| Which systems and mixins compose the model? | `visualize(S; kind = :hierarchy)` |
| What happens during one generated update? | `visualize(S; kind = :flow)` |
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
`visualize(df, x, y)` uses saved data. Variable selectors are supported for
`kind = :dependency` and `kind = :flow`. `visualize!` remains a plot-layer
operation, not a way to modify these static diagrams.

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
changes the displayed labels to the declared aliases. Labels
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

A pair selects directed variable paths between its endpoints: this includes `c`
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
For path selection, the generated phases of one variable are treated as one.
For example, `:rate => :output` follows `rate → mass → output` even when `mass`
is an accumulating state. Context phases that enforce update order remain
distinct, so they do not create paths between unrelated variables.
The picture still shows the original update stages and edges. A variable path
can span timesteps; it is not necessarily a continuous directed path through
one timestep's schedule. The [phenology example](@ref phenology-tutorial)
demonstrates a path through an accumulated thermal state.

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

### [Computation flow diagram](@id visualization-flow)

Dependency graphs emphasize relationships; flow diagrams follow the compiler's
operation order, with expressions, conditions, and state carried across updates.
Both are static views, not runtime traces or complete control-flow graphs.
Here, "flow" means computation, not a stock-and-flow model of physical fluxes.

Use this view to follow selected variables or a local process through an
update. It is not a compact overview of a large model: every included variable
has a lane, including fixed inputs, and omitted inputs still appear at the
boundary. Start with a variable or a `source => target` path, then expand the
selection as needed. Inspect child systems separately.

```@example structure
visualize(GrowingDegree; kind = :flow)
```

Read downward: each numbered row is an operation in the compiler's topological
order, not elapsed time or an observed runtime event. Lanes represent variables
and arrows represent reads, not messages between objects in a UML sequence
diagram. Fixed inputs have lanes but no update row. Numbers refer to positions in
the complete schedule, so they can have gaps. Every expression names its target,
so it can be read without tracing a lane back to the top. A row and its expression
share the same baseline. Curved merges and crossing bridges route declared inputs
into an operation; they do **not** encode delay or addition of values.
Bridges cross active vertical guides or carry segments, not unused background
guides or the gaps between carry segments.

| Mark | Meaning |
|:---|:---|
| Filled circle / open circle | Derived value / remembered value |
| Square / rounded square | State update / opaque child call |
| Parallelogram | Driver input |
| Diamond | Condition or post-update rate cache, identified by the operation note |
| Double rounded square / hexagon | Production / opaque solver operation |
| Small open circle / small square on an input lane | Local read / boundary read |
| Blue solid arrow / ochre dotted arrow | Declared input / condition (`when`) |
| Pale vertical guide | Repeated occurrences of one variable, not an extra dependency |
| Gray solid cut side rail | Value, counter, or memory retained across updates |
| Teal dash-dot cut side rail | Cached rate from the previous post-update stage |

Color identifies the role of a connection, not a variable's importance, value,
or biological process. Arrowheads and junctions match their connections;
variable symbols and text stay neutral. Thin, pale guides recede behind actual
reads and cross-update rails. The legend uses the same styles as the diagram,
and line patterns and cut rails retain their meanings without color.

An accumulating state needs two operations, but not two repeated timesteps:

```@example structure
@system ThermalFlow(Controller) begin
    Tb: base_temperature => 5            ~ preserve(parameter, u"°C")
    T: temperature       => [8, 12, 16]  ~ drive(u"°C")
    rate(T, Tb) => max(T - Tb, 0u"K")    ~ track(u"K")
    total(rate): thermal_time            ~ accumulate(u"K*d")
    mature(total) => total >= 50u"K*d"   ~ flag(once)
end

visualize(ThermalFlow; kind = :flow)
```

The main operation, `total ← total + rate(total) * Δt`, consumes the
**previously cached rate** and the elapsed clock interval; the post operation,
`rate(total) ← rate`, caches a new rate for a later update.
`capture` has the same rate cache but replaces, rather than accumulates, its
value. With `time = elapsed`, either state uses `Δ(elapsed)` instead of `Δt`:
the difference between that time variable's current and cached readings.
The solid side rail denotes retained value, counter, or memory.
For `accumulate(reset = ...)`, the post stage also caches the reset decision;
the operation note identifies it. `drive` samples an array stored at
construction, so its source table is not presented as a fresh read each step.

The expression column is derived from declaration bodies, local argument
aliases, and supported tags. It includes conditions and their fallback, clamps,
one-shot behavior, and rate caching. It is a compact explanatory rendering,
not executable Julia: routine unit conversion and generated temporary variables
are omitted. Tag settings equal to their declaration defaults are omitted too;
non-default solver bounds, tolerances, and root selection remain visible.
A single-system `produce` queues a child only while its collection is empty,
in addition to any `when` condition. It does not use an LLM or infer biological
labels from names.
An outer `begin … end` is reduced to its statements; multiple statements are
parenthesized and separated by semicolons. Private names use `Owner._name`,
keeping identically named fields from different mixins distinct without exposing
internal mangled names. Use `look` for complete declarations, aliases,
units, and documentation.

The same name, vector, and path selectors work here:

```@example structure
visualize(ThermalFlow, :total; kind = :flow, depth = 0)
```

This retains `total`'s operations in their original order. Its omitted input
`rate` remains visible as a gray boundary lane, not as a shortcut through a
hidden computation. This differs from a dependency graph, whose unselected
nodes are simply absent. Selecting more variables does not reorder the full
system's schedule.

Nested systems remain opaque calls. Qualified references preserve the
connection to their owner, with the prefix drawn lightly:

```@example structure
diagram = visualize(StructuralGrowth; kind = :flow)
```

Here `supply` is a call and `supply.rate` is a boundary read. Inspect
`visualize(Supply; kind = :flow)` for the child's own flow diagram. There is no
recursive flattening, runtime trace, or configuration-specific active-path
analysis. Initialization/configuration, context subcycling, solver iterations,
and production internals are not expanded. In particular, `integrate` is
quadrature, not a temporal accumulator; its internals stay opaque.

The flow diagram uses the existing Makie/CairoMakie renderer. It displays as SVG in
notebooks, lists numbered operations in a terminal, and can be saved without
a display server. The figure is created only for graphical display or export;
the text output uses the same plan and notes without creating a Makie figure.
Multiline expressions stay aligned with their numbered row:

```@example structure
show(stdout, MIME"text/plain"(), diagram)
```

Its only style option is
`style = (fontsize = 10,)`, which scales text and spacing together. The monospace
font is bundled with Makie; no system font installation is needed. The canvas
grows with variables and rows instead of clipping or shrinking them.

```@example structure
Cropbox.writeimage("flow.svg", diagram)
Cropbox.writeimage("flow.pdf", diagram)
Cropbox.writeimage("flow.png", diagram; px_per_unit = 2)
nothing # hide
```

Download the [Flow SVG](flow.svg), [PDF](flow.pdf), or [PNG](flow.png).
Graphviz-specific `style`, `engine`, and `writedot` options do not apply to
flow diagrams. `visualize!` does not add layers to this diagram.

### Display, grouping, and export

Dependency and hierarchy graphs use bundled Graphviz, not the Makie/UnicodePlots plotting
backends. Notebooks display SVG; terminals show a compact text summary without
running Graphviz. A failed automatic SVG render shows a fallback notice and
logs the underlying exception as a warning; explicit image export reports
the rendering error.

```@example structure
g = visualize(StructuralGrowth; style = (group = :system,))
```

The grouped graph displays directly in a notebook. Its stored rendering options
also apply to exports:

```@example structure
Cropbox.writeimage("structure.svg", g)
Cropbox.writeimage("structure.pdf", g)
Cropbox.writedot("structure.dot", g)
nothing # hide
```

Download the [grouped SVG](structure.svg), [PDF](structure.pdf), or
[Graphviz source](structure.dot). `group = :system` clusters variables by their
declaring system or mixin; it does not expand child-system instances.

Pass rendering options in `style` to `visualize`, leaving the underlying graph
unchanged. `writeimage` and `writedot` inherit them and can override individual
options with their own `style`. Supported keys are `alias`, `group`, `rankdir`, `ratio`,
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

### Structural graph API

```@docs
visualize(::Type{<:System})
Cropbox.writedot
Cropbox.writeimage(::AbstractString, ::Cropbox.Graph)
```
