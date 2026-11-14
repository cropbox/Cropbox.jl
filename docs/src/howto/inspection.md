# [Inspect and Visualize Models](@id inspection-workflow)

Inspection should come before editing configuration or selecting output. Cropbox
provides complementary views of a model type, an instance, and simulation data.

## List parameters

```@example inspectflow
using Cropbox

@system InspectDemo(Controller) begin
    rate: growth_rate => 2 ~ preserve(parameter, u"g/hr")
    mass(rate)             ~ accumulate(u"g")
end

parameters(InspectDemo)
```

Useful options are:

- `alias=true`: show aliases rather than short names;
- `recursive=true`: include parameters in nested systems;
- `exclude=(...)`: omit infrastructure or already visited systems;
- `scope=module`: choose where defaults are evaluated when inspecting a type.

For an instance, `parameters(s)` reports current values rather than declaration
defaults.

## Inspect declarations and values

```@example inspectflow
look(InspectDemo)
look(InspectDemo, :mass)
```

On an instance, `look` also displays the current value.

```@example inspectflow
s = instance(InspectDemo)
look(s, :mass)
```

The macro form avoids quoting a variable name:

```@example inspectflow
@look InspectDemo.mass
```

`@look s.f(x)` has another meaning: it evaluates a function-like Cropbox
variable. Use the function form `look(s, :f)` when the goal is declaration
inspection.

## Inspect dependency relationships

`look` shows declarations; `visualize` shows their relationships without running
a simulation:

```@example inspectflow
d = visualize(InspectDemo)
```

```@example inspectflow
h = visualize(InspectDemo; kind = :hierarchy)
```

The default `kind = :dependency` follows variables and generated update stages;
`kind = :hierarchy` follows mixins and child systems, omitting nested `Context`
infrastructure. Dashed hierarchy edges denote mixins. Cropbox uses its bundled
Graphviz executable to render either graph as SVG on supported platforms. A
static copy can be written for documentation:

```@example inspectflow
Cropbox.writeimage("dependency", d; format = :svg)
Cropbox.writeimage("hierarchy", h; format = :svg)
nothing # hide
```

Download the generated [dependency graph](dependency.svg) or
[hierarchy graph](hierarchy.svg).

The text representation remains available without invoking Graphviz.

To inspect just the inputs to `mass`, select its upstream neighborhood:

```@example inspectflow
visualize(InspectDemo, :mass; direction = :up)
```

See [Model structure](@ref visualization-structure) for shape and arrow meanings,
system grouping, and the difference between selecting neighborhoods and paths.
These are static declaration graphs, not runtime traces. Explain the scientific
relationships alongside the graph rather than inferring them from node shape.

For worked model examples, compare the accumulating state in
[Logistic Growth](@ref logistic-growth-tutorial), the grouped input-to-state path in
[Weather-driven Phenology](@ref phenology-tutorial), and a local process in
[SimpleCrop](@ref simplecrop-tutorial).

## Navigate an instance

`dive(s)` opens a terminal menu for walking through nested systems and values.
It is not interactive in Jupyter; there it falls back to a simpler display. Use
`look`, property access, or explicit output paths in notebooks.

## Read values in Julia code

```@example inspectflow
s.rate'
value(s.mass)
```

Postfix `'` is concise for interactive work. `value(...)` is clearer in helper
functions. Do not assume a system field is a bare number.

## Visualize an existing result

For a side-by-side guide to argument combinations and their resulting plots,
see [Choose a plotting call](@ref visualization-calls). That reference contains
the full examples for both Makie and UnicodePlots.

`visualize` works directly with vectors, and `visualize!` adds another series
to the same result:

```@example inspectflow
x = collect(1:5)
p = visualize(x, 2 .* x; kind = :line, name = "2x", ylim = (0, 15))
visualize!(p, x, 3 .* x; kind = :line, name = "3x")
```

The explicit range reserves space for both curves, including on a fixed-size
terminal canvas.

This form is useful for calculated curves that do not require a simulation.
For model output, retain the DataFrame and name its columns explicitly.

```@example inspectflow
r = simulate(InspectDemo; stop = 4u"hr", target = :mass)
visualize(r, :time, :mass; kind = :line)
```

The same function accepts vectors or DataFrames and can also run a system
itself.

```@example inspectflow
visualize(InspectDemo, :time, :mass;
    stop = 4u"hr",
    kind = :line,
)
```

## Interactively explore parameters

In JupyterLab or Notebook with `jupyter-server-proxy`, `manipulate` adds widgets
that update a visualization as parameter values change.

```julia
manipulate(InspectDemo, :time, :mass;
    parameters = InspectDemo => (
        rate = 0:0.5:3,
    ),
    stop = 4u"hr",
    kind = :line,
)
```

Use interaction to explore sensitivity and plausible ranges. For reproducible
analysis, record explicit configurations and run them with `simulate`; an
interactive widget is not a substitute for a saved experiment design.

## Plot a parameter response

For a model with a configurable input, `xstep` creates the configurations needed
for a response curve.

```@example inspectflow
visualize(InspectDemo, :rate, :mass;
    xstep = InspectDemo => :rate => 0:0.5:3,
    stop = 2u"hr",
    kind = :line,
)
```

Use `group` for separate series and two input ranges for a heatmap. For
analysis beyond quick exploration, construct configurations explicitly with
`@config`, call `simulate`, and retain the resulting DataFrame.

## Compare observations and estimates

`visualize(obs, Model, ...)` overlays observations and model output, while
`visualize(obs, Model, target; index=...)` can produce an observation-versus-
estimate plot. See [Evaluate and Calibrate Models](@ref evaluation-tutorial) for a
complete workflow.
