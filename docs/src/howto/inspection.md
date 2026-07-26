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

`look` is the stable human-readable view. Package authors can also inspect the
dependency representation used during code generation:

```julia
graph = Cropbox.dependency(InspectDemo)
```

This returns an implementation-oriented graph rather than a publication-ready
diagram. Its nodes distinguish update stages as well as variables, so use it
for debugging declaration order and cycles, not as a saved public API format.
For model documentation, describe the important process dependencies explicitly.

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

`plot` can work directly with vectors, and `plot!` adds another series to an
existing plot:

```julia
x = 1:5
p = plot(x, 2 .* x; kind = :line)
plot!(p, x, 3 .* x; kind = :line)
```

This form is useful for calculated curves that do not require a simulation.
For model output, retain the DataFrame and name its columns explicitly.

```@example inspectflow
r = simulate(InspectDemo; stop = 4u"hr", target = :mass)
visualize(r, :time, :mass; kind = :line)
```

`plot` works directly with vectors or DataFrames. `visualize` adds model-aware
convenience methods and can run a system itself.

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
estimate plot. See [Evaluation and Calibration](@ref evaluation-tutorial) for a
complete workflow.
