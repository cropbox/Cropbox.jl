# [Evaluation and Calibration](@id evaluation-tutorial)

Model evaluation compares estimates with observations. Calibration searches a
parameter space for configurations that improve a selected metric. Keep these
steps separate: evaluation is meaningful on any data set, while calibration
must be judged on data not used by the optimizer.

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

## Available metrics

The current implementation accepts:

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

## Evaluate a system directly

```@example evaluation
@system LinearGrowth(Controller) begin
    time(context.clock.time)       ~ track(u"d")
    rate                     => 10 ~ preserve(parameter, u"g/d")
    mass(rate)                     ~ accumulate(u"g")
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

## Visualize residual structure

```julia
visualize(obs2, LinearGrowth, :mass;
    index = :time,
    config,
    stop = 3u"d",
)
```

Also plot residuals against time, temperature, development stage, and fitted
values. These views reveal timing errors and heteroscedasticity that a scalar
metric cannot.

## Calibrate one parameter

`calibrate` uses BlackBoxOptim internally. It can be computationally expensive,
so the full search is shown but not executed during this documentation build.

```julia
fitted = calibrate(LinearGrowth, obs2;
    config,
    index = :time,
    target = :mass,
    parameters = LinearGrowth => :rate => (0u"g/d", 20u"g/d"),
    stop = 3u"d",
    metric = :rmse,
    optim = (MaxSteps = 1000,),
)
```

The result is a `Config` that can be merged with the base scenario.

```julia
estimate = simulate(LinearGrowth;
    config = @config(config + fitted),
    stop = 3u"d",
    target = :mass,
)
```

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

Every configuration contributes residuals to the objective. Ensure observation
indices uniquely identify rows across environments.

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
8. Evaluate the fitted configuration on held-out data.
9. Report bounds, metric, weights, optimizer options, package versions, and any
   stochastic model seeds.

`calibrate` currently calls `Random.seed!(0)` immediately before BlackBoxOptim.
Record the Cropbox version because this fixed optimizer initialization is
framework behavior rather than a configurable optimizer option.

Calibration cannot repair a structural error, an incorrect unit, or a mismatched
observation index. Diagnose those before expanding the search.
