# [Evaluate and Calibrate Models](@id evaluation-tutorial)

Model evaluation compares estimates with observations. Calibration searches a
parameter space for configurations that improve a selected metric. Keep these
steps separate: evaluation is meaningful on any data set, while calibration
must be judged on data not used by the optimizer.

This page is the final part of the
specification → simulation → visualization and evaluation workflow. Start here
after the model definition, scenarios, and output contract have already been
checked.

## [Sensitivity analysis](@id sensitivity-analysis)

Sensitivity analysis asks how changes in model parameters affect an output. It
does not calibrate the model or establish agreement with observations. Cropbox
uses GlobalSensitivity.jl for Morris, Sobol, and eFAST analysis.

```@example sensitivity
using Cropbox, GlobalSensitivity, Random

@system SensitivityExample(Controller) begin
    a    => 0.5 ~ preserve(parameter)
    b    => 0.5 ~ preserve(parameter)
    c    => 0.5 ~ preserve(parameter)
    sign => 1.0 ~ preserve(parameter)

    response(a, b, c, sign) => sign * (a + 2b + 3c) ~ track
    total(response)                                 ~ accumulate
end

bounds = SensitivityExample => (; a = (0, 1), b = (0, 1), c = (0, 1))
result = analyze(SensitivityExample;
    target = :total, parameters = bounds, stop = 2,
    method = Morris(num_trajectory = 20), gsa = (; rng = Xoshiro(42)),
)
result.table
```

The returned table can be plotted directly. Here the mean absolute Morris
effects are 2, 4, and 6: over two hours, the full specified ranges of `a`, `b`,
and `c` change the accumulated output by those amounts.

```@example sensitivity
visualize(result.table, :means_star, :parameter;
    backend = :Makie,
    xlab = "Mean absolute effect", ylab = "Parameter",
    xlim = (0, 7), ycat = unique(result.table.parameter),
    legend = false,
)
```

The default form reads the **final model state**, even if the last saved
snapshot is earlier. `stop` must be explicit: use `stop = 0` for an initialized
static model. Endpoint analysis avoids recording a full trajectory by default.

For a time-series summary, supply a function that returns one finite real
scalar, optionally with units:

```@example sensitivity
summary = analyze(df -> maximum(df.total), SensitivityExample;
    target = :total, parameters = bounds, stop = 3, snap = 2u"hr",
    method = Morris(num_trajectory = 20), gsa = (; rng = Xoshiro(42)),
)
summary.table
```

This callback receives a **new DataFrame from each simulation**, not a saved
table. The model is rerun for every sampled parameter combination. Here the
last recorded time is two hours, so the callback summarizes snapshots through
that time, not the final state at three hours. Its output is named `:summary`.
There is no general `analyze(saved_df)` interface: arbitrary stored runs do not
necessarily have the sampling design required by a sensitivity method.

### Methods and execution options

Use `method = :morris`, `:sobol`, or `:efast` for default method settings. For
other settings, pass a native method object. Execution options are collected in
`gsa`, separate from simulation options:

| Method | Constructor options | `gsa` options |
|---|---|---|
| `Morris(...)` | `num_trajectory`, `total_num_trajectory`, `len_design_mat`, `p_steps`, `relative_scale` | `rng` |
| `Sobol(...)` | `order`, `nboot`, `conf_level` | required `samples`; optional `Ei_estimator` |
| `eFAST(...)` | `num_harmonics` | required `samples`; optional `rng` |

```@example sensitivity
variance = analyze(SensitivityExample;
    target = :response, parameters = bounds, stop = 0,
    method = :efast, gsa = (; samples = 1024, rng = Xoshiro(42)),
)
variance.table
```

```@example sensitivity
visualize(variance.table, :S1, :parameter;
    backend = :Makie,
    xlab = "First-order sensitivity index", ylab = "Parameter",
    xlim = (0, 1), ycat = unique(variance.table.parameter),
    legend = false,
)
```

For this additive response with equal independent uniform input ranges, the
first-order variance contributions are approximately `1/14`, `4/14`, and
`9/14`. `ST` is close to `S1` because there are no interactions. These
dimensionless fractions are not the same measure as the Morris effects above.

`samples` is not a universal simulation budget: its interpretation and actual
model-evaluation count depend on the method. Morris does not use it. Unsupported
options, misspellings, and `batch = true` are rejected. The current adapter
evaluates parameter sets sequentially. `gsa.rng` controls supported sampling
methods; the separate `seed` keyword retains the model's usual `instance`
semantics.

For a stochastic model, choose a repeatable model `seed` or an explicit
replication strategy; uncontrolled simulation noise can confound parameter
sensitivity.

Bounds define independent uniform inputs and must be finite, increasing pairs
for continuous parameters.
They are converted to the parameters' model units. Fixed values belong in
`config`; integer parameters are not rounded into continuous samples.
Sampling is normalized to `[0, 1]` before mapping to the physical bounds.
Consequently, Morris effects describe changes per full specified input range
and retain output units (squared for variances). `relative_scale = true` uses
the native relative-effect definition and is dimensionless. Sobol and eFAST
indices are dimensionless. Importance always depends on the chosen bounds.
Affine outputs such as Celsius are converted to absolute units before numerical
analysis; temperature effects are reported as differences in kelvin.

### Conditions and returned results

Supply either one `config` or a list of `configs`. All conditions use the same
sampled parameter combinations, but their outputs are not averaged. Multiple
targets are also retained separately:

```@example sensitivity
conditions = [SensitivityExample => :sign => s for s in (1, -1)]
separate = analyze(SensitivityExample;
    target = [:response, :total], parameters = bounds,
    configs = conditions, stop = 2,
    method = Morris(num_trajectory = 20), gsa = (; rng = Xoshiro(42)),
)
separate.table
```

The result is a named tuple with `table` and `raw`. The table includes the
configuration index, output name, system, parameter, and physical bounds.
Morris adds `means`, `means_star`, and `variances`; Sobol and eFAST add `S1` and
`ST`. `raw` preserves the original result, including requested Sobol interactions
and confidence intervals. Raw matrix rows follow configuration order, then
target order; columns follow parameter order. Raw magnitudes have been stripped
of units for the numerical backend, while the table restores Morris units.

### A growing model

For a time-dependent example, screen the maximum biomass reached in a small
logistic growth model. The callback summarizes each newly simulated trajectory;
the bounds vary growth rate and carrying capacity independently.

```@example sensitivity
@system SensitivityGrowth(Controller) begin
    rate     => 0.2 ~ preserve(parameter, u"d^-1")
    capacity => 100 ~ preserve(parameter, u"g")

    mass(mass, rate, capacity) => rate * mass * (1 - mass / capacity) ~ accumulate(init = 1, u"g")
end

growth = analyze(df -> maximum(df.mass), SensitivityGrowth;
    target = :mass, parameters = SensitivityGrowth => (; rate = (0.1, 0.3), capacity = (50, 150)),
    config = Clock => :step => 1u"d", stop = 30u"d",
    method = Morris(num_trajectory = 20), gsa = (; rng = Xoshiro(42)),
)
growth.table
```

```@example sensitivity
visualize(growth.table, :means_star, :parameter;
    backend = :Makie,
    xlab = "Mean absolute effect", ylab = "Parameter",
    xlim = (0, 100), ycat = growth.table.parameter[sortperm(growth.table.means_star)],
    legend = false,
)
```

The effects retain the output unit, grams, even though the parameters have
different units. They compare changes over the **whole specified input range**,
not equal physical increments. Their magnitudes and ranking depend on those
bounds, the 30-day horizon, and the chosen summary. This small example
demonstrates the workflow, not biological validation or sampling convergence.

Non-finite model outputs and empty callback data raise errors. A sampled output
that is constant cannot yield variance-based indices; it is reported as an
error rather than a misleading zero sensitivity. Failed runs are not silently
discarded or replaced with other parameter samples.

GlobalSensitivity 2.12.9 has a known [two-parameter eFAST frequency-design
issue](https://github.com/SciML/GlobalSensitivity.jl/issues/229). Affected sample
counts raise an explanatory error before model runs; Cropbox does not change
the requested sample count. Morris or Sobol can be used instead. The native
Sobol range interface also emits an upstream QuasiMonteCarlo design warning;
Cropbox preserves that warning and does not silently substitute another design.

```@docs
analyze
```

## Compare two data frames

```@example evaluation
using Cropbox
using DataFrames

obs = DataFrame(
    time = [1, 2, 3]u"d",
    observed_mass = [10, 20, 30]u"g",
)

est = DataFrame(
    time = [1, 2, 3]u"d",
    predicted_mass = [11, 19, 31]u"g",
)

evaluate(obs, est;
    index = :time,
    target = :observed_mass => :predicted_mass,
    metric = :rmse,
)
```

The pair maps an observation column to an estimate column. Rows are joined by
the index rather than assumed to be in the same order.

For two tables, omitting `index` uses their `:time` columns. When index names
differ, use a pair such as `index = :hour => :time`; compatible units are
normalized without modifying either input. DataFrame views are also accepted.
Unmatched rows are excluded, as are rows missing any of the requested targets.
If no complete matching rows remain, evaluation raises an `ArgumentError`
instead of returning a score. Non-finite values such as `NaN` are not dropped.

## Choose a metric

RMSE and MAE are convenient starting points. Both the two-table and system
forms support the following metrics:

| Metric | Symbol | Notes |
|---|---|---|
| Root mean square error | `:rmse` | Default; retains the target unit |
| Normalized RMSE | `:nrmse` | RMSE divided by observation mean |
| Root mean square percentage error | `:rmspe` | Relative residuals |
| Mean absolute error | `:mae` | Less sensitive to large errors than RMSE |
| Mean absolute percentage error | `:mape` | Relative absolute residuals |
| Nash–Sutcliffe efficiency | `:ef` | Relative to the observation mean model |
| Refined index of agreement | `:dr` | Agreement measure with bounded interpretation |

Percentage metrics are undefined or unstable when observations are zero or near
zero. Inspect the data before selecting a metric. A low aggregate error can also
hide stage-specific bias, so pair metrics with residual plots.

Error metrics are better when lower. Efficiency and agreement (`:ef` and `:dr`)
are better when higher, with one indicating a perfect match. `calibrate`
minimizes its objective, so use an error metric or convert a higher-is-better
score to a loss such as `1 - score`; do not minimize `:ef` or `:dr` directly.

## Evaluate a system directly

```@example evaluation
@system LinearGrowth(Controller) begin
    time(context.clock.time) ~ track(u"d")
    rate => 10               ~ preserve(parameter, u"g/d")
    mass(rate)               ~ accumulate(u"g")
end

obs2 = DataFrame(
    time = [1, 2, 3]u"d",
    mass = [9, 21, 29]u"g",
)

config = @config Clock => :step => 1u"d"

evaluate(LinearGrowth, obs2;
    config,
    index = :time,
    target = :mass,
    stop = 3u"d",
    metric = :mae,
)
```

Cropbox creates snapshots at observation indices, normalizes compatible index
units, joins rows, and applies the metric. Empty or nonmatching output therefore
usually indicates an index, time-zone, stop, or snapshot problem rather than a
metric problem.

## Multiple targets

```@example evaluation
obs3 = DataFrame(
    time = [1, 2, 3]u"d",
    mass = [9, 21, 29]u"g",
    rate = [10, 10, 10]u"g/d",
)

evaluate(LinearGrowth, obs3;
    config,
    index = :time,
    target = [:mass, :rate],
    stop = 3u"d",
)
```

Multiple targets return a tuple of metrics. Their dimensions and magnitudes may
differ, which becomes important during multi-objective calibration.

## Calibrate one parameter

Use the first three observations for calibration and keep later observations
out of the search. This small example runs during the documentation build with
a limited optimizer budget. It demonstrates the workflow, not a validation of
a biological growth model.

```@example evaluation
calibration_data = obs2
validation_data = DataFrame(
    time = [4, 5, 6]u"d",
    mass = [41, 48, 62]u"g",
)

fitted = calibrate(LinearGrowth, calibration_data;
    config,
    index = :time,
    target = :mass,
    parameters = LinearGrowth => :rate => (0, 20),
    stop = 3u"d",
    metric = :rmse,
    optim = (MaxSteps = 100, PopulationSize = 20, TraceMode = :silent),
)
```

The bounds inherit `rate`'s declared unit `u"g/d"`. The result is a `Config`
that can be merged with the base scenario. The fitted rate should be close to
`9.9u"g/d"`; exact optimizer results can vary between package versions.

## Evaluate validation data

Use the same fitted configuration for both scores. The observations reserved
for validation were not supplied to `calibrate`.

```@example evaluation
fitted_config = @config(config + fitted)

scores = DataFrame(
    data = ["calibration", "validation"],
    rmse = [
        evaluate(LinearGrowth, calibration_data;
            config = fitted_config, index = :time, target = :mass, stop = 3u"d"),
        evaluate(LinearGrowth, validation_data;
            config = fitted_config, index = :time, target = :mass, stop = 6u"d"),
    ],
)
```

This example uses later observations for validation. In a real study, using
separate site-years, treatments, or independent experiments for validation may
be more suitable than splitting rows from one trajectory.

Join predictions to observations before subtracting them. Keeping the columns
named makes the residual direction explicit:

```@example evaluation
predictions = simulate(LinearGrowth;
    config = fitted_config,
    index = :time,
    target = :predicted => :mass,
    stop = 6u"d",
)

residuals = innerjoin(validation_data, predictions; on = :time)
residuals.residual = residuals.predicted .- residuals.mass
@assert nrow(residuals) == nrow(validation_data) # hide
residuals
```

A negative residual means underprediction. Always check the number of matched
rows: an inner join omits unmatched indices, and evaluation does not interpolate
between model updates.

```@example evaluation
p = visualize(residuals, :time, :residual;
    backend = :Makie,
    kind = :scatterline,
    xlab = "Time",
    ylab = "Predicted - observed mass",
    title = "Validation residuals",
    legend = false,
)
visualize!(p, [4, 6]u"d", [0, 0]u"g";
    kind = :line,
    color = :lightgray,
    legend = false,
)
```

Also examine residuals against temperature, development stage, and fitted
values. Patterns in these plots can reveal timing errors or changing error
spread that a single score hides.

## Calibrate across environments

Pass `configs` when one biological parameter set should fit several site-years.
Each entry must already contain its shared base settings as well as its
environment-specific patch; unlike `simulate`, `calibrate` does not accept a
nonempty `config` and `configs` together.

```julia
fitted = calibrate(Model, observations;
    configs = environment_configs,
    index = [:year, :date],
    target = [:emergence, :maturity],
    parameters = Phenology => (
        Tb = (-5, 15),
        requirement = (100, 2000),
    ),
    stop = :finished,
)
```

Calibration calculates each environment's metric separately, then sums those
scores for each target. In contrast, `evaluate(...; configs)` pools the matching
rows before calculating a metric. These objectives are not interchangeable: a
sum of site-year RMSE values gives each site-year one score, while pooled RMSE
also reflects how many observations each site-year contains. Ensure observation
indices uniquely identify rows across environments and choose the objective
deliberately.

## Multiple objectives

For several targets, `weight` changes their aggregate importance. With
`pareto=true`, calibration returns configurations along a Pareto frontier rather
than one weighted compromise.

```julia
frontier = calibrate(Model, observations;
    configs = environment_configs,
    index = [:site, :date],
    target = [:leaf_area, :bulb_mass],
    parameters = parameter_bounds,
    weight = [0.5, 0.5],
    pareto = true,
    stop = :finished,
)
```

Equal numerical weights do not imply equal scientific importance when targets
have different metrics or scales. Normalize deliberately and report the choice.

## A defensible workflow

1. Validate input units, indices, and missing data.
2. Run the base model and inspect process-level outputs.
3. Choose identifiable parameters with defensible bounds.
4. Split environments or years into calibration and validation sets.
5. Start with a small optimizer budget and one target.
6. Inspect convergence and residual structure.
7. Increase the budget only after the pipeline is correct.
8. Evaluate the fitted configuration on the validation data.
9. Report bounds, metric, weights, optimizer options, package versions, and any
   stochastic model seeds.

`calibrate` currently calls `Random.seed!(0)` immediately before BlackBoxOptim.
Record the Cropbox version because this fixed optimizer initialization is
framework behavior rather than a configurable optimizer option.

Calibration cannot repair a structural error, an incorrect unit, or a mismatched
observation index. Diagnose those before expanding the search.
