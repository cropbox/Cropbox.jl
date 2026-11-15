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

`look` is the stable declaration view. Two qualified structural helpers expose
complementary graphs:

```@example inspectflow
d = Cropbox.dependency(InspectDemo)
```

```@example inspectflow
h = Cropbox.hierarchy(InspectDemo; skipcontext = true)
```

`dependency` follows variables and generated update stages; it is useful for
checking evaluation order and cycles. `hierarchy` follows mixins and child
systems; dashed edges denote mixins. Cropbox uses its bundled Graphviz
executable to render either graph as SVG on supported platforms. A static copy
can be written for documentation:

```@example inspectflow
Cropbox.writeimage("dependency", d; format = :svg)
Cropbox.writeimage("hierarchy", h; format = :svg)
nothing # hide
```

Download the generated [dependency graph](dependency.svg) or
[hierarchy graph](hierarchy.svg).

The text representation remains available without invoking Graphviz.

These helpers are qualified because their graph representation is
implementation-oriented rather than a stable serialization format. Explain the
scientific relationships in the surrounding text instead of asking readers to
infer model meaning from every generated stage.

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

To simulate and plot in one call, pass the system type instead of a DataFrame,
as in the [Quick Start](@ref quick-start). The
[Visualization API](@ref visualization-calls) compares both call forms.

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

For a model with a configurable input, create one configuration per input value
and compare one time point from each run. Here `snap` keeps only the state at
two hours.

```@example inspectflow
configs = @config !(InspectDemo => :rate => 0:0.5:3)
responses = simulate(InspectDemo;
    configs,
    stop = 2u"hr",
    snap = s -> s.context.clock.time' == 2u"hr",
    target = [:rate, :mass],
)

visualize(responses, :rate, :mass;
    kind = :line,
    xlab = "Growth rate",
    ylab = "Biomass after two hours",
    legend = false,
)
```

There is one point per growth rate, with biomass equal to the rate multiplied
by two hours. Without selecting a time point, this dynamic model contributes
every saved snapshot at each rate; joining those rows creates a sawtooth rather
than the intended response curve.

Keep `responses` for later analysis. The [Visualization API](@ref
Visualization1) also shows the `xstep` shorthand for direct response plots,
`group` for separate series, and two input ranges for a heatmap.

## Compare observations and estimates

`visualize(obs, Model, ...)` overlays observations and model output, while
`visualize(obs, Model, target; index=...)` can produce an observation-versus-
estimate plot. See [Evaluate and Calibrate Models](@ref evaluation-tutorial) for a
complete workflow.
