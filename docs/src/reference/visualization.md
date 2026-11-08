# [Visualization](@id Visualization1)

Cropbox provides one main visualization family and an optional interactive
wrapper. The same calls work with existing data or with a model that still
needs to be simulated.

| Function | Start with | What it does |
|---|---|---|
| `visualize`, `visualize!` | vectors, a `DataFrame`, a system, or data plus a system | draw existing data or run any needed simulations and draw the result |
| `manipulate` | a callback or `visualize` arguments | add parameter widgets in a supported notebook |
| `Cropbox.reset_manipulate` | no arguments | reset widget connections after a failed notebook refresh |

For a saved analysis, it is usually clearest to call `simulate`, keep its
`DataFrame`, and plot that table. Direct system visualization is convenient for
quick response curves, comparisons, and checks while developing a model.

The public call families are:

| Call shape | Result |
|---|---|
| `visualize(X, Y)` or `visualize(df, x, y)` | visualize existing arrays or table columns |
| `visualize(System, x, y)` | simulate one system and plot its trajectory or response |
| `visualize([System1, System2], x, y)` | compare compatible systems |
| `visualize(df, System, x, y)` | overlay observations and a simulated trajectory |
| `visualize(obs, System, y; index)` | observation-versus-estimate plot |
| `visualize(obs, est, y; index)` | compare observations with an already simulated `DataFrame` |
| `visualize(System, x, y, z)` | two-factor heatmap or contour plot |
| `visualize!` | append to an existing `Plot` and return the same wrapper |

Every form returns Cropbox's `Plot` wrapper and accepts the same labels, units,
limits, kinds, and backend selection.

## Common plotting forms

The examples below use one small trajectory model and one static response
model.

```@example visref
using Cropbox
using DataFrames

@system VisualTrajectory(Controller) begin
    rate => 1.0 ~ preserve(parameter, u"g/hr")

    mass(rate)                     ~ accumulate(u"g")
    reached(mass) => mass >= 3u"g" ~ flag
end

@system VisualResponse(Controller) begin
    input => 0.0 ~ preserve(parameter)
    slope => 1.0 ~ preserve(parameter)

    response(input, slope) => slope * input ~ track(min = 0)
end

series = DataFrame(
    hour = (0:4)u"hr",
    observed = [0.1, 1.2, 1.9, 3.2, 3.8]u"g",
    smooth = [0, 1, 2, 3, 4]u"g",
    reached = [false, false, false, true, true],
)

nothing
```

### Vectors and DataFrames

```julia
visualize(X::Vector, Y::Vector; options...)
visualize(X::Vector, [Y1, Y2]; options...)
visualize(df, x, y; options...)
visualize(df, x, [y1, y2]; options...)
```

For a `DataFrame`, `x` and `y` may be column names as symbols or strings. They
may also be an expression evaluated column by column, such as `:(SWC / depth)`.
The result is useful for a derived quantity that does not need to become a model
variable. Functions used inside the expression must be visible in the calling
Julia session; for a saved analysis, a named derived column is easier to test
and reuse.

Array-based calls currently dispatch on concrete `Vector` values. Use
`collect(range)` before passing a range directly.

```@example visref
visualize(series, :hour, :observed;
    kind = :scatterline,
    title = "Observed mass",
    xlab = "Time",
    ylab = "Mass",
    legend = false,
)
```

Passing several `y` columns draws several series. `names` controls their legend
labels; `legend` is the legend title, not a Boolean switch for individual
series.

Provide one entry per series in `names` and `colors`, or leave them as `nothing`
to use the defaults. A mismatched length raises an `ArgumentError` instead of
silently omitting series. This also applies to grouped curves and model
comparisons.

```@example visref
visualize(series, :hour, [:observed, :smooth];
    kind = :line,
    names = ["observation", "reference"],
    legend = "Series",
    ylab = "Mass",
)
```

### Grouped DataFrames

Use `group` to split existing rows by one column or several columns. This does
not run a simulation. Groups appear in first-occurrence order; their values
provide the default legend labels.

```@example visref
grouped = simulate(VisualTrajectory;
    configs = @config(!(VisualTrajectory => :rate => [1, 2, 3])),
    stop = 4, verbose = false,
)
visualize(grouped, :time, :mass; group = :rate, kind = :line)
```

For example, `group = [:site, :treatment]` groups by both columns. With several
`y` columns, each group contains one series per column, in the supplied order.
Custom `names` and `colors` need one entry per resulting series. DataFrame views
are also supported; the input table is not modified.

The keyword is the same for model and table inputs: `group` on a system expands
configurations and simulates them, while `group` on a table selects columns.

### Plot kinds

Two-dimensional plots support these `kind` values:

| `kind` | Use |
|---|---|
| `:scatter` | separate observations; the default |
| `:line` | a continuous ordered trajectory |
| `:scatterline` | points and a connecting line |
| `:step` | stages, counts, or Boolean state changes |
| `:hline` | one or more horizontal reference lines |
| `:vline` | one or more vertical reference lines |

`step` automatically treats Boolean values and other repeated categories as
ordered levels. Supply `ycat` when their display order must be explicit.
For Makie step plots, appending new categories keeps the existing order and
adds the new levels at the end.

Terminal layers share the initial category order. List all categories in
`ycat` before adding layers; an undeclared category raises an error rather than
being drawn under the wrong label. Grouped tables infer the shared order from
all groups.

```@example terminalcategories
using Cropbox
p = visualize([0, 1], [:sown, :emerged];
    backend = :UnicodePlots,
    kind = :step, ycat = [:sown, :emerged, :mature], legend = false)
visualize!(p, [0, 1], [:emerged, :mature]; kind = :step, legend = false)
ans[] # hide
```

```@example visref
visualize(series, :hour, :reached;
    kind = :step,
    ylab = "Threshold reached",
    legend = false,
)
```

An initial horizontal line needs `xlim`; an initial vertical line needs
`ylim`. When the line is appended to a plot, Cropbox reuses that plot's limits.

```@example visref
plain_series = DataFrame(
    x = 0:4,
    observed = [0.1, 1.2, 1.9, 3.2, 3.8],
    smooth = 0:4,
)

p = visualize(plain_series, :x, :observed;
    kind = :scatter,
    name = "observation",
    xlab = "Time",
    ylab = "Mass",
)
visualize!(p, plain_series, :x, :smooth;
    kind = :line,
    name = "reference",
)
visualize!(p, 3;
    kind = :hline,
    name = "threshold",
    color = :lightgray,
)
```

The one-value `:hline` and `:vline` helpers use the y-axis and x-axis units,
respectively. Compatible units are converted, even when the axes have
different dimensions:

```@example visref
p_units = visualize(series, :hour, :observed; kind = :scatter)
visualize!(p_units, 3000u"mg";
    kind = :hline,
    name = "threshold",
)
```

`visualize!` changes and returns the same Cropbox `Plot`. Reference lines and
text annotations can be added through this API without modifying the backend
object:

```@example visref
visualize!(p, [1, 3], [4, 2]; kind = :line, color = :gray, linestyle = :dot, name = "")
visualize!(p, 2, 3.5, "Reference\nline"; align = :center)
```

With Makie, automatic axis limits expand to include appended series. Explicit
`xlim` or `ylim` stays fixed, and a new explicit limit in `visualize!` replaces
the previous setting. Automatic margins follow Makie; reference lines and text
retain the existing limits.
UnicodePlots uses a fixed canvas: grouped plots determine their complete range
before drawing, but when manually appending to a terminal plot, supply the full
range when creating it.

`linestyle` accepts `:solid` (the default), `:dash`, `:dot`, `:dashdot`, and
`:dashdotdot`, or a vector with one style per y series. UnicodePlots draws solid lines and warns when another style is
requested. Text uses data coordinates and the existing axis units, converting
compatible unitful values. It does not change the axis limits or add a legend
entry. `align` accepts `:left` (the default), `:center`, and `:right`.

On a calendar axis, pass a `Date` or `DateTime` directly as the horizontal
annotation coordinate. This works with both backends:

```@example dateannotations
using Cropbox, Dates
dates = collect(Date(2026, 1, 1):Day(1):Date(2026, 1, 3))
p = visualize(dates, [1, 3, 2];
    backend = :Makie,
    kind = :line, legend = false)
visualize!(p, Date(2026, 1, 2), 2, "Measurement")
```

To save a graphical result, use `Cropbox.writeimage`:

```@example visref
p = visualize(series, :hour, :observed; backend = :Makie, kind = :line)

Cropbox.writeimage("observed.png", p)
Cropbox.writeimage("observed.svg", p)
Cropbox.writeimage("observed.pdf", p)
p # hide
```

Download these exact exports as [PNG](observed.png), [SVG](observed.svg), or
[PDF](observed.pdf).

The function returns the output filename and needs no additional package
installation or import. The filename extension selects PNG, SVG, or PDF;
`Cropbox.writeimage("observed", p; format = :pdf)` appends the extension.
Additional options such as `px_per_unit = 2` are passed to CairoMakie's `save`.
Image export requires `backend = :Makie`; UnicodePlots terminal output is not
converted automatically. Notebook display keeps CairoMakie's default PNG output.
For direct Makie use, `p[]` (or `p'`) still extracts the underlying `Figure`.

## Visualize a simulation

```julia
visualize(SystemType, x, y;
    config = (), group = (), xstep = (),
    base = nothing, stop = nothing, snap = nothing,
    options...)
```

This form calls `simulate` with `x` and `y` as output variables, then renders
the result. The usual simulation meanings of `base`, `stop`, and `snap` apply.

```@example visref
visualize(VisualTrajectory, :time, :mass;
    config = VisualTrajectory => :rate => 1,
    stop = 4u"hr",
    kind = :line,
    ylab = "Mass",
    legend = false,
)
```

When `y` is a vector, all targets are drawn from the same simulation output.
This is the form used for leaf gas-exchange limitation rates, garlic organ
mass, and soil-water components in the tutorials.

```@example visref
@system VisualPartition(VisualTrajectory) begin
    leaf_mass(mass) => 0.6mass ~ track(u"g")
    bulb_mass(mass) => 0.4mass ~ track(u"g")
end

visualize(VisualPartition, :time, [:leaf_mass, :bulb_mass, :mass];
    stop = 4u"hr",
    kind = :line,
    names = ["leaf", "bulb", "total"],
    ylab = "Mass",
)
```

### Parameter response curves

`xstep` varies the variable used on the x-axis. `group` makes one series for
each value of another parameter. Both accept the same system-to-parameter pair
shape used by `@config`.

```@example visref
visualize(VisualResponse, :input, :response;
    xstep = VisualResponse => :input => 0:0.25:4,
    group = VisualResponse => :slope => [0.5, 1.0, 1.5],
    kind = :line,
    ylab = "Response",
)
```

For a grouped curve, the group parameter becomes the default legend title and
its values become the series labels. Pass `names` and `legend` to replace them.
If `names` is a symbol, Cropbox reads the unique value of that output column and
uses it as each label. The latter is useful when a label is determined
indirectly by configuration.

Use `xstep` with a static or snapshot-like response. If the system advances for
many steps, every snapshot from every configuration is placed in the same
curve; in that case it is usually clearer to call `simulate`, select the
desired time rows, and plot the resulting table.

### Compare systems

Pass a vector of system types to compare compatible outputs. `configs`,
`names`, and `colors` are parallel vectors and must match the systems in order.

```@example visref
@system FastVisualTrajectory(VisualTrajectory) begin
    rate => 1.5 ~ preserve(parameter, u"g/hr")
end

visualize([VisualTrajectory, FastVisualTrajectory], :time, :mass;
    configs = [(), ()],
    names = ["baseline", "fast"],
    colors = [:steelblue, :darkorange],
    stop = 4u"hr",
    kind = :line,
)
```

The systems do not need to share an implementation, but each must expose the
requested x and y paths. Omit `configs`, or leave it empty, to use an empty
configuration for every system. Supply a parallel vector explicitly when the
positional pairing should be especially clear in teaching or analysis code.

### Append simulations with `visualize!`

Use the mutating form when the layers are assembled conditionally or at
different points in an analysis. `nothing` is accepted as the initial plot, but
starting with `visualize` is usually easier to read.

```@example visref
p = visualize(VisualTrajectory, :time, :mass;
    config = VisualTrajectory => :rate => 1,
    stop = 4u"hr",
    kind = :line,
    names = ["baseline"],
    legend = "Model",
    colors = [:steelblue],
)

visualize!(p, FastVisualTrajectory, :time, :mass;
    stop = 4u"hr",
    kind = :line,
    names = ["fast"],
    colors = [:darkorange],
)
```

All appended layers must use compatible axis units. `visualize!` does not
retain a simulation table, so call `simulate` explicitly when those values are
needed for later statistics or export.

Appended calls inherit the existing backend and legend position. There is no
need to repeat `backend`; explicitly selecting a different backend for an
existing visualization is an error.

## Observations and model estimates

There are two distinct comparison plots.

### Overlay trajectories

```julia
visualize(observations, SystemType, obs_x => model_x, obs_y => model_y;
    config, stop, options...)
```

Cropbox draws observations as points and model output as a line. Pairs map
differently named columns; omit the pairs when both names already match.

```@example visref
observations = DataFrame(
    hour = (0:4)u"hr",
    measured = [0.1, 1.2, 1.9, 3.2, 3.8]u"g",
)

visualize(observations,
    VisualTrajectory,
    :hour => :time,
    :measured => :mass;
    config = VisualTrajectory => :rate => 1,
    stop = 4u"hr",
    name = "observation",
    names = ["model"],
    ylab = "Mass",
)
```

Pass a vector of systems and a parallel `configs` vector to overlay several
models on the same observations.

### Observation versus estimate

Omit the x argument and supply `index`. Cropbox joins observations and estimates
at matching indices, draws points, and adds the 1:1 line.

```@example visref
visualize(observations,
    VisualTrajectory,
    :measured => :mass;
    index = :hour => "context.clock.time",
    config = VisualTrajectory => :rate => 1,
    stop = 4u"hr",
    name = "model",
)
```

A saved simulation table can replace the system argument. No simulation is
rerun, and neither input table is modified:

```@example visref
estimates = simulate(VisualTrajectory; target = :mass, stop = 4u"hr")
visualize(observations, estimates, :measured => :mass;
    index = :hour => :time,
    name = "saved model",
)
```

Here pairs map observation column names to estimate column names, including
the `index` columns. Use a single name when the names match, for example
`visualize(obs, est, :mass; index = :time)`. Both tables may contain unrelated
columns with the same names. Compatible index units such as hours and minutes
are converted before matching; rows are matched by index, not by their order.
Multiple index columns are supported, for example `index = [:site, :time]`.
Only matched rows are plotted, and an empty match is an error. Duplicate keys
follow DataFrames' inner-join semantics: every matching pair is included.

Use `visualize!(p, obs, est, y; index, options...)` to append to an existing
plot. A scalar target uses `name`; a vector of targets uses `names` and
`colors`, just like the system-based comparison.

A vector target draws one observation-versus-estimate series for each target.
For several model specifications of one target, pass named tuples with
`system`, `config`, or `configs` fields:

```@example visref
models = [
    (; system = VisualTrajectory,
       config = VisualTrajectory => :rate => 0.9),
    (; system = VisualTrajectory,
       config = VisualTrajectory => :rate => 1.1),
]

visualize(observations, models, :measured => :mass;
    index = :hour => "context.clock.time",
    names = ["slow", "fast"],
    stop = 4u"hr",
)
```

These plots join on the index, so missing points, incompatible units, time-zone
differences, or duplicate indices can change which rows appear. Check the
joined data with `evaluate` or an explicit DataFrames join when a point is
unexpectedly absent.

## Heatmaps and contours

```julia
visualize(SystemType, x, y, z;
    config = (), xstep = (), ystep = (),
    base = nothing, stop = nothing, snap = nothing,
    options...)
```

`xstep` and `ystep` form a factorial grid. The result is plotted as a heatmap by
default. This is the pattern used for the nitrogen-by-water-potential response
in the Leaf Gas Exchange tutorial.

```@example visref
visualize(VisualResponse, :input, :slope, :response;
    xstep = VisualResponse => :input => 0:0.25:4,
    ystep = VisualResponse => :slope => 0.25:0.25:2,
    kind = :heatmap,
    xlab = "Input",
    ylab = "Slope",
    zlab = "Response",
    aspect = 1.4,
)
```

The same factorial result can be rendered as contours:

```@example visref
visualize(VisualResponse, :input, :slope, :response;
    backend = :Makie,
    xstep = VisualResponse => :input => 0:0.25:4,
    ystep = VisualResponse => :slope => 0.25:0.25:2,
    kind = :contour,
    zgap = 0.5,
    zlabgap = 1,
    xlab = "Input",
    ylab = "Slope",
    zlab = "Response",
    aspect = 1.4,
)
```

Three-column `visualize(df, x, y, z)` uses the same renderer. Set
`kind=:contour` for contour lines. `zlim` fixes the color or contour range,
`zgap` controls contour spacing, and `zlabgap` requests labels at a chosen
interval. Contour rendering and the gap options are currently more complete in
the Makie backend than in the terminal backend. Grid rows may be unordered;
missing cells and `missing` values are not interpolated. Duplicate coordinates are
rejected. Terminal heatmaps need evenly spaced x and y coordinates; Makie also
accepts irregular spacing.

```@example terminalheatmap
using Cropbox, DataFrames
grid = DataFrame([(; x, y, z = x + y) for x in 1:15 for y in 1:15])
visualize(grid, :x, :y, :z;
    backend = :UnicodePlots,
    zlab = "Response", zlim = (0, 30))
ans[] # hide
```

DataFrame views work here too, so filtering a saved table does not require
copying it before plotting:

```@example visref
grid = DataFrame(x = [1, 1, 2, 2], y = [1, 2, 1, 2], z = [2., 3., 4., 5.])
visualize(view(grid, :, :), :x, :y, :z; zlab = "Response")
```

## Labels, units, limits, and backends

The main two-dimensional options are:

| Option | Meaning |
|---|---|
| `kind` | `:scatter`, `:line`, `:scatterline`, or `:step` |
| `title`, `xlab`, `ylab` | plot and axis labels |
| `name`, `names` | one series label or several series labels |
| `legend`, `legendpos` | legend title/visibility and inside position |
| `color`, `colors` | one color or parallel series colors |
| `linestyle` | line pattern, defaulting to `:solid` |
| `xlim`, `ylim` | displayed data limits |
| `xunit`, `yunit` | units used for conversion and axis labels |
| `ycat` | explicit category order for a step plot |
| `aspect` | requested width-to-height relation |
| `backend` | `:Makie` or `:UnicodePlots` |

For three-column plots, `zlab`, `zlim`, `zgap`, and `zlabgap` control the color
or contour dimension. `legendpos = (x, y)` places a Makie legend at
relative coordinates: `x` locates its left edge from the panel's left edge,
and `y` offsets its centre downward from the panel's centre. For example,
`(0.1, -0.3)` places it near the upper left. The terminal backend warns and
ignores that option. Makie also accepts named positions such as `:lt` and `:rb`
for a series legend.

Set `legend=false` to hide the legend. Units are inferred from arrays or
DataFrame columns. An explicit `xunit` or `yunit` converts compatible values
before plotting; it does not reinterpret an incompatible number. `ZonedDateTime`
columns are converted to `DateTime` because the graphical backend does not
accept zoned values directly.

Cropbox chooses Makie in Jupyter, Pluto, VS Code, and Documenter, and
UnicodePlots in a plain terminal. Set `backend` when output must be identical
across environments. Use `visualize` and `visualize!` for drawing and annotations
so that notebook code does not depend on a backend's internal plot structure.

Backend behavior is not completely identical:

| Feature | Makie | UnicodePlots |
|---|---|---|
| line, scatter, and step | supported | supported |
| `:scatterline` | points plus line | line rendering |
| text annotations | supported | supported within terminal resolution |
| non-solid `linestyle` | supported | solid lines with a warning |
| heatmap | supported | supported on a regular grid |
| contour | supported | warns and falls back to a heatmap |
| inside `legendpos` | supported | ignored with a warning |
| `zgap`, `zlabgap` | supported for contours | ignored with a warning |

Use `backend = :Makie` for graphical output, contour labels, and inside
legends. Use `:UnicodePlots` for fast
terminal diagnostics.

### Dates in terminal plots

The terminal backend accepts `Date` and `DateTime` values on the horizontal
axis, including scatter plots. Axis labels retain the calendar values.

```@example visdates
using Cropbox, Dates

dates = collect(Date(2026, 1, 1):Day(1):Date(2026, 1, 4))
visualize(dates, [1, 3, 2, 4];
    backend = :UnicodePlots,
    xlab = "Date", ylab = "Value", legend = false)
ans[] # hide
```

### Makie backend

Cropbox installs and loads Makie and its CairoMakie renderer as regular
dependencies. No separate installation or `using CairoMakie` is needed to
display a Makie plot in a notebook. Makie is the default in graphical
environments; select `backend = :Makie` explicitly when running in a terminal.

```@example visref
using Cropbox

p = visualize([0, 1, 2], [0, 1, 4];
    backend = :Makie,
    kind = :line, name = "Model", legendpos = (0.1, -0.3))
visualize!(p, [0, 1, 2], [0, 1.1, 3.8]; name = "Observed")
visualize!(p, 1, 3, "Example")
Cropbox.writeimage("figure.pdf", p) # hide
p # hide
```

The [PDF export](figure.pdf) contains the same plotted result.

The built-in Classic style follows Cropbox's Gadfly colors, lighter text,
compact legends, and calendar labels. It uses Makie's bundled Noto Sans,
with tick-label size 10 and axis-label/title size 12. Cropbox bundles
[Noto Sans CJK KR Regular](https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf)
as a fallback for Korean, Chinese, and Japanese,
so these labels do not depend on system fonts or an extra download.
The style is scoped to the figure and does not change the global Makie theme.
Cropbox does not expose theme selection; use Makie directly for custom styling.

The CJK font is © 2014-2021 Adobe, licensed under the
[SIL Open Font License 1.1](https://openfontlicense.org/open-font-license-official-text/).
Its original copyright and license metadata is preserved in the unmodified font file.

This adapter supports lines, scatter, scatterlines, categorical steps,
horizontal/vertical lines, heatmaps, contours (including labels), and text.
It retains units and explicit limits; in particular `zlim` is the exact color
range, not Gadfly's sometimes expanded tick range. Grid rows may be unordered;
missing grid cells remain blank. Dates use Makie's native calendar conversion.

### Migrating from Gadfly

Normal `visualize` and `visualize!` calls keep their signatures and options,
but the output is not pixel-identical. Font fallback, tick labels, legend
layout, and heatmap color ranges may differ.

Cropbox no longer installs Gadfly or supports it as a backend. Replace explicit
`backend = :Gadfly` with `backend = :Makie`. Code that accesses `Gadfly.Plot`
fields or uses `Cropbox.Gadfly.SVG` or `PDF` must also change: use public
`visualize!` calls for annotations and layers, and the export examples above
for saving figures. For example, replace `p[] |> Cropbox.Gadfly.PDF("figure.pdf")`
with `Cropbox.writeimage("figure.pdf", p)`.

Archived workshop and course notebooks may continue to use their original
versioned environments or Docker image digests. Updating those materials is
separate from this package migration. `manipulate` now uses Bonito instead of
Interact/WebIO; its return value is a Bonito-backed display object, not an
Interact widget.

## Common failures

- A vector of systems requires parallel `configs`, `names`, and `colors` in the
  same order. In particular, `configs` must have the same length as the system
  vector.
- A heatmap requires a complete, regularly ordered factorial grid. Missing
  combinations are better handled by constructing and checking a `DataFrame`
  before plotting.
- Appended layers must have compatible units. `xunit` and `yunit` convert
  compatible quantities; they do not assign dimensions to unrelated values.
- Appended calls inherit the existing backend; do not select a different one.
- A grouped response curve may contain every snapshot from every configuration.
  Select one time point explicitly when a dynamic run would otherwise join
  unrelated trajectories.
- Observation-versus-estimate plots use an inner join. Missing, duplicated, or
  differently zoned index values can silently reduce or multiply the points;
  inspect the joined table when the count is unexpected.
- Backend warnings usually indicate a presentation limitation, not a failed
  simulation. Re-run with `backend = :Makie` before changing model equations.

## Interactive parameter controls

The callback form receives a configuration made from the current widget values:

```julia
manipulate(c -> visualize(VisualTrajectory, :time, :mass;
        config = c,
        stop = 4u"hr",
        kind = :line,
    );
    parameters = VisualTrajectory => :rate => 0:0.25:2,
    config = VisualTrajectory => :rate => 1,
)
```

The convenience form sends its positional and remaining keyword arguments to
`visualize`:

```julia
manipulate(VisualTrajectory, :time, :mass;
    parameters = VisualTrajectory => :rate => 0:0.25:2,
    config = VisualTrajectory => :rate => 1,
    stop = 4u"hr",
    kind = :line,
)
```

Numeric ranges and arrays make sliders; arrays of symbols or enum values and
dictionaries make drop-down controls; Booleans make check boxes. Dictionary
keys are the displayed labels and their values are passed to the callback.
An explicit `config` sets the initial selection; otherwise sliders start at
the middle element and drop-down controls start at the first option.

Slider readouts update while dragging, but the model is recalculated only when
the change is committed, such as when the mouse button is released. The
callback receives the selected values with their model units restored, merged
with the baseline configuration.

Callbacks can also return numbers, strings, tables, or other displayable values:

```julia
manipulate(c -> c[:VisualTrajectory][:rate];
    parameters = VisualTrajectory => :rate => 0:0.25:2,
    config = VisualTrajectory => :rate => 1,
)
```

JupyterLab 4 and Notebook 7 need `jupyter-server-proxy` installed in the Python
environment that runs Jupyter:

```sh
python -m pip install jupyter-server-proxy
```

Restart the Jupyter server after installation. Cropbox's Docker image includes
this dependency. No WebIO extension, separate Bonito import, or widget macro
is needed: execute the `manipulate(...)` cell to display the controls and plot.
A live Julia kernel is required for recalculation; saved notebook or HTML
output does not run the model on its own.

Each IJulia output uses an isolated frame and connection so widgets in different
notebooks do not share browser state. The `manipulate(...)` call is unchanged.

The Docker image uses notebook-relative proxy URLs, so forwarding Jupyter to a
different host port does not require a widget setup cell.

With the default Bonito configuration, Cropbox requests an automatically
assigned port before displaying the first widget. Separate notebook kernels
can therefore run widgets at the same time without selecting ports manually.
An existing Bonito server, a nondefault port, or an explicit proxy is left unchanged.

When updating older workshop or course notebooks, remove this WebIO
initialization cell:

```julia
Cropbox.Interact.WebIO.setup(:ijulia)
```

It initialized WebIO in the older notebook/sysimage environment. Interact is
no longer a Cropbox dependency, so that line now errors. It does not need a
replacement for an ordinary first run. Archived notebooks using their original
Cropbox environment should keep their original setup.

!!! warning "Notebook reloads with Bonito 5.2"
    A normal browser refresh can reconnect while the kernel and widget session
    remain alive. Saved output can show the initial values rather than the last
    live selection; re-run the relevant `manipulate(...)` cell when resuming work.
    If controls remain unresponsive, recover without restarting Julia by running:

    ```julia
    Cropbox.reset_manipulate()
    ```

    Then re-run the interactive output cells. This resets all Bonito widget
    sessions in the current Julia kernel, not the model definitions or other
    Julia variables. Existing calibration results remain available; there is no
    need to restart the kernel or run every cell again. Widget selections return
    to each call's initial configuration. Existing port and proxy settings are
    preserved. Do not run this inside each `manipulate` call. This is a recovery step, not a
    required initialization cell or a fix for saved outputs. An upstream fix is
    proposed in [Bonito #423](https://github.com/SimonDanisch/Bonito.jl/pull/423).

    For teaching notebooks, keep a separate cell containing this command,
    labelled "Run only if widgets stop responding after a refresh". Students
    can run that cell and then the desired `manipulate(...)` cells without
    remembering a recovery command. Skip it during normal use.

Outside IJulia, `manipulate` still returns a Bonito `App` for an HTML-capable
display, rather than silently returning a single static plot.

Treat a widget as an exploration tool. Save the selected values as an explicit
`Config` before using them in a reproducible analysis.
