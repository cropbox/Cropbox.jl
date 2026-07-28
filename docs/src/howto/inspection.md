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

```julia
d = Cropbox.dependency(InspectDemo)
h = Cropbox.hierarchy(InspectDemo; skipcontext = true)
```

`dependency` follows variables and generated update stages; it is useful for
checking evaluation order and cycles. `hierarchy` follows mixins and child
systems; dashed edges denote mixins. Cropbox uses its bundled Graphviz
executable to render either graph as SVG on supported platforms. A static copy
can be written for documentation:

```julia
Cropbox.writeimage("dependency", d; format = :svg)
Cropbox.writeimage("hierarchy", h; format = :svg)
```

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

`visualize` works directly with vectors, and `visualize!` adds another series
to the same result:

```julia
x = collect(1:5)
p = visualize(x, 2 .* x; kind = :line)
visualize!(p, x, 3 .* x; kind = :line)
```

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

In a Jupyter Notebook with a working WebIO provider, `manipulate` adds widgets
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

## Sweep an input on a plot

For a model with a configurable input, `xstep` creates the configurations needed
for a response curve.

```@example inspectflow
visualize(InspectDemo, :rate, :mass;
    xstep = InspectDemo => :rate => 0:0.5:3,
    stop = 2u"hr",
    kind = :line,
)
```

Use `group` for separate series and two sweep dimensions for a heatmap. For
analysis beyond quick exploration, construct configurations explicitly with
`@config`, call `simulate`, and retain the resulting DataFrame.

## Compare observations and estimates

`visualize(obs, Model, ...)` overlays observations and model output, while
`visualize(obs, Model, target; index=...)` can produce an observation-versus-
estimate plot. See [Evaluate and Calibrate Models](@ref evaluation-tutorial) for a
complete workflow.
