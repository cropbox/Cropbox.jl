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
The diagrams display graphically in notebooks. Expand **Terminal output (REPL)**
below an example to see the same result as text. Structural diagrams do not
take a plotting `backend` option.

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

g = visualize(StructuralGrowth)
```

```@raw html
<details class="terminal-example"><summary>Terminal output (REPL)</summary>
```

The text lists variables and their generated phases in update order.

```@example structure
show(stdout, MIME"text/plain"(), g) # hide
```

```@raw html
</details>
```

```@example structure
g = visualize(StructuralGrowth; kind = :hierarchy)
```

```@raw html
<details class="terminal-example"><summary>Terminal output (REPL)</summary>
```

The text lists the systems in the hierarchy. The diagram shows how they are related.

```@example structure
show(stdout, MIME"text/plain"(), g) # hide
```

```@raw html
</details>
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

This key is for dependency and hierarchy graphs. For `kind = :flow`, see the
[flow diagram legend](@ref visualization-flow-legend).

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

A flow diagram follows one update in compiler order, showing expressions,
conditions, and retained state. It describes potential reads, not an observed
run or a stock-and-flow model. For a large model, start with one variable or
a `source => target` path; inputs outside the selection remain visible.

```@example structure
g = visualize(GrowingDegree; kind = :flow)
```

```@raw html
<details class="terminal-example"><summary>Terminal output (REPL)</summary>
```

```@example structure
show(stdout, MIME"text/plain"(), g) # hide
```

```@raw html
</details>
```

Read the numbered rows from top to bottom. Each selection starts at 1 and
numbers only the visible operations, in compiler order. Variables occupy lanes; a fixed
input can have a lane without an operation. Horizontal arrows on the same
row lead to one target, not from one input to the next. Lane headings stay
horizontal unless adjacent labels would crowd each other; then all headings
rotate together by 72 degrees.

#### [Flow diagram legend](@id visualization-flow-legend)

**Operation symbols.** In the figure, the shape at the arrow tip tells you
what Cropbox does on that row. Its outline and pale backdrop share a role color:
blue for a driver input, violet for a binding, green for accumulation, counters and
cached rates, ochre for flag tests, and terracotta for field and child-system updates.
Computed values and opaque operations are charcoal; remembered values are slate.
In a wide terminal, the target usually shows
the *phase* instead: `◓` pre, `○` main, `◒` post. Two operations have their own
terminal targets: `△` saves a rate and `▽` marks a binding.

| Target in the figure | Operation |
|:---|:---|
| `●` Filled circle / `○` open circle | Compute a value (`track`) / keep the first eligible value (`remember`). |
| `□` Square | Update an accumulated value, captured increment, or counter (`accumulate`, `capture`, `advance`). |
| Rounded square / double rounded square | Update a field or child system / update or queue children with `produce`. |
| `▱` Parallelogram | Read a stored driver input (`drive`). |
| `◇` Diamond | Evaluate a flag (`flag`). |
| `△` Upward triangle / `▽` downward triangle | Save a rate for the next update / show a local callable's bound inputs, without calling it. |
| `⬡` Hexagon | A `solve`, `bisect`, `integrate`, or `wrap` operation; its internal steps are not expanded. |

**Connections and colors.** Follow horizontal arrows *toward* the target.
Reads, self-loops, and carried values meet the rim of the target's pale disc,
not the inner glyph. A self-read normally leaves the top and returns from the
upper left; a second self-read for a condition uses the lower half.
A small open circle on a source lane marks a selected input; a small open
square marks an input outside the selection (for example, `supply.rate`).
In a wide terminal, `●` marks either kind of **input**, not the result.
An unmarked crossing is not an input.

```@setup structure
let shaft = "M2 8H30", tip = "M25 5.5 30 8 25 10.5", dash = (solid = "none", dash = "5 3", dot = "1 3")
    for (name, path, head) in (
        (:read, shaft, tip), (:binding, shaft, tip), (:control, shaft, tip),
        (:value, "M24 1v0.2m0 1.8v1m0 2v2q0 2-3 3l-4 3", "M17.5 11.5 17 14l3-.3"),
        (:rate,  "M10 1v0.2m0 1.8v1m0 2v2q0 2 3 3l4 3", "M16.5 11.5 17 14l-3-.3"),
        (:guide, "M17 1v8m0 2v.3m0 2v.3", ""),
    )
        (; color, linestyle) = Cropbox.FLOW_STYLES[name]
        write("flow-key-$name.svg", """
            <svg xmlns="http://www.w3.org/2000/svg" width="34" height="16" fill="none"
                 stroke="$color" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round">
              <path d="$path" stroke-dasharray="$(dash[linestyle])"/><path d="$head"/>
            </svg>""")
    end
end
```

| Figure | Terminal | How to read it |
|:---|:---|:---|
| ![](flow-key-read.svg) Solid blue arrow | `●──→○`; `x ← a, b` in a list | Read the marked inputs for this target. Several inputs on one row are not a chain. |
| ![](flow-key-binding.svg) Dashed violet arrow | `●╌╌→▽`; `f ⇠ k` in a list | `f` binds `k`. Its current value is read **when `f` is invoked**, not at the numbered binding row. |
| ![](flow-key-control.svg) Dotted ochre arrow | `[when ready]` or `[reset restart]` | Read a control. The terminal shows the tag instead of a separate control arrow. `[once]` is a latch, not another input. |
| Arrow looping back to its own lane | `↺` in wide output | A row reads its own variable. This is distinct from carrying a value across updates. |
| ![](flow-key-value.svg) Slate rail, right of the lane | `← mass [prev update]` | Carry a value, counter, or memory. A name means the same row retained it. |
| ![](flow-key-rate.svg) Green rail, left of the lane | `← #2 [prev update]` / `→ #1 [next update]` | Carry a cached rate between two rows. `#` refers to the other row in this selection, not a variable or timestep. |
| ![](flow-key-guide.svg) Pale gray center line | Lane heading only | Follow the same variable to its last use; the dotted background guide and horizontal row dividers carry no value. |
| — | `┬─`, `├─`, `└─` in a list | More inputs to the **same row** on a narrow terminal. |

Fading rail ends at the top bring state in from the previous update; fading ends
at the bottom carry it into the next. If terminal colors are enabled,
input lines are light blue, controls yellow, row numbers and cross-references
gray, and rate targets and update labels cyan. The symbols also work without color.

**Reading a row.** Find the target from its mark and lane heading. On the
right, a tinted bold label names the behavior when needed; monospace shows
the model expression or setting with Julia syntax highlighting, and italics
describe the operation. Paired delimiters use a muted gray so names stand out
in expressions such as `valid[i[]]`. Conditions come last. One split badge pairs
the dark key with its expression on a pale background (e.g. `when = ready`); a bare
`once` needs only the dark segment. A badge is a declaration, not a runtime result.
Expression-only rows do not gain a label. The terminal keeps the target
names and tags, but omits expressions and action text.

#### Worked examples

An accumulating state needs two operations, but not two repeated timesteps:

```@example structure
@system ThermalFlow(Controller) begin
    Tb: base_temperature => 5            ~ preserve(parameter, u"°C")
    T: temperature       => [8, 12, 16]  ~ drive(u"°C")
    rate(T, Tb) => max(T - Tb, 0u"K")    ~ track(u"K")
    total(rate): thermal_time            ~ accumulate(u"K*d")
    mature(total) => total >= 50u"K*d"   ~ flag(once)
end

tf = visualize(ThermalFlow; kind = :flow)
```

```@raw html
<details class="terminal-example"><summary>Terminal output (REPL)</summary>
```

**Wide terminal (100 columns).** Here `rate` is a model variable, while `△`
marks the operation that saves the rate for `total`.

```@example structure
show(IOContext(stdout, :displaysize => (24, 100)), MIME"text/plain"(), tf) # hide
```

**Narrow terminal (40 columns).** When lanes do not fit, the inputs are
listed by name. The rate-saving row lists its input, then points to the next update.

```@example structure
show(IOContext(stdout, :displaysize => (24, 40)), MIME"text/plain"(), tf) # hide
```

Follow the paired `#` numbers between the two `total` rows. In contrast,
`mature` retains its own flag value, so its previous-update link names `mature`.

```@raw html
</details>
```

Read the two rows on the `total` lane together. The first says **accumulate**: add
the **previously cached rate** multiplied by elapsed time. The later row shows
**accumulate**, then `rate` and *save rate*: the input from `total(rate)` is
saved for the next update. A `capture` replaces its value with that same
increment rather than adding it. A declared `time = elapsed` identifies the
clock used to measure the interval.

An `if` in a body stays model code, not a control tag. For `when = mask[1]`
only `mask` is a condition input; `when = mask[idx[]]` also reads `idx`.
In a declaration argument or tag, the diagram shows possible reads: both sides
of `&&` or `||`, each operand of `lo[] < T[] <= hi[]`, and the condition and
both alternatives of `on[] ? lo[] : hi[]`. Only the chosen alternative runs.
In `f(x[]).field`, the field belongs to the result: the row reads `x`, not
`x.field`. It also reads `f` if `f` is a model variable. The broadcast
`f.(xs[])` has the same model inputs and call bindings as `map(f, xs[])`.

A variable used both in the calculation and as a control has both arrows.
A tag describes behavior, not a runtime observation or a universal on/off
switch. For `accumulate` and `capture`, a false `when` saves a **zero rate**;
it does not skip the main row. An accumulator samples `reset` alongside that
rate even if `when` is false. If set, the next main row starts from `init`
before adding the increment. An ordinary `track` uses `init` or zero when
its condition is false; a flag clears unless already latched by `once`.
For `produce`, the existing child is updated independently of `when`. Only
the later row queues new children for construction next update; a single
child can be queued only while empty. A driver reads the input stored at
construction, not the source table anew. With a bisection, only an explicit
`min` or `max` adds a clipping row; `lower` and `upper` are search bounds.
An outer `begin … end` is reduced to its statements; multiple statements are
parenthesized and separated by semicolons. Private names use `Owner._name`,
keeping identically named fields from different mixins distinct without exposing
internal mangled names. Use `look` for complete declarations, aliases,
units, and documentation.

Name, vector, and path selectors use the compiler's dependency graph. A flow
arrow can show a read that is not an edge in that graph: for example, with
`dotted(v = sum(f.(xs[])))`, the diagram shows `xs` as an input, but
`:xs => :dotted` can raise an `ArgumentError` because there is no compiler path.
Select the target with `depth = 0` to see its declared reads instead:
`visualize(S, :dotted; kind = :flow, depth = 0)`. For the accumulator above:

```@example structure
visualize(ThermalFlow, :total; kind = :flow, depth = 0)
```

This retains `total`'s operations in their original order. Its omitted input
`rate` remains visible as a gray boundary lane, not as a shortcut through a
hidden computation. This differs from a dependency graph, whose unselected
nodes are simply absent. Selecting more variables does not reorder the full
system's schedule.

This model both updates a child system and calls a local function:

```@example structure
@system GrowthAllocation(StructuralGrowth) begin
    share(gain; f)   => f * gain   ~ call(u"g/hr")
    root_rate(share) => share(0.3) ~ track(u"g/hr")
end

diagram = visualize(GrowthAllocation; kind = :flow)
```

```@raw html
<details class="terminal-example"><summary>Terminal output (REPL)</summary>
```

```@example structure
show(stdout, MIME"text/plain"(), diagram) # hide
```

```@raw html
</details>
```

`supply.rate` is a boundary read; inspect `visualize(Supply; kind = :flow)`
for the child's update. The dashed arrow into `share` identifies `gain` as a
bound input. Here `root_rate` invokes `share` with the argument `0.3`; another
consumer could pass the callable without invoking it. Each local binding is
shown once, including nested calls. Initialization, child steps and solver
internals are not expanded.

#### Graphical export

The Makie/CairoMakie figure is created only for notebook display or export.
Flow diagrams default to `fontsize = 11`, slightly larger than the tick labels
on Classic plots. Use `style = (fontsize = 10,)` for the Classic tick-label
size, or `style = (fontsize = 12,)` for a larger diagram. Text, symbols, and
spacing scale together. The canvas grows to fit its contents; the monospace
and italic fonts are bundled with Makie.

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
