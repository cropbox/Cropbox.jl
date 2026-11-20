# [Predator–Prey Model](@id lotka-volterra-tutorial)

This tutorial preserves the Lotka–Volterra predator–prey example used in the
original Cropbox manual. It is not a crop model, but it is a compact way to
learn two patterns that occur throughout crop modeling: several states changing
together and a base process being extended without copying the whole
specification.

Add the packages used below to your active Julia environment, then run the
blocks in order in the same session:

```julia
using Pkg
Pkg.add(["Cropbox", "CSV", "DataFrames"])
```

## Start from the Lotka–Volterra equations

Let prey population ``N`` and predator population ``P`` follow

```math
\frac{dN}{dt} = bN - aNP, \qquad
\frac{dP}{dt} = caNP - mP.
```

The parameters ``b``, ``a``, ``c``, and ``m`` remain fixed during one run.
Both populations are accumulated states, and each rate depends on the current
value of both states.

| Symbol | Meaning | Cropbox role |
|---|---|---|
| ``b`` | prey birth rate | configurable preserved value |
| ``a`` | predation rate | configurable preserved value |
| ``c`` | conversion efficiency | configurable preserved value |
| ``m`` | predator mortality rate | configurable preserved value |
| ``N``, ``P`` | current populations | coupled accumulated states |

## Declare a reusable process

```@example lotka
using Cropbox
using CSV
using DataFrames

@system PredatorPrey begin
    t(context.clock.time): elapsed_time ~ track(u"yr")

    b: prey_birth_rate         => 0.6  ~ preserve(parameter, u"yr^-1")
    a: predation_rate          => 0.02 ~ preserve(parameter, u"yr^-1")
    c: conversion_efficiency   => 0.5  ~ preserve(parameter)
    m: predator_mortality_rate => 0.5  ~ preserve(parameter, u"yr^-1")

    N0: prey_initial_population     => 20 ~ preserve(parameter)
    P0: predator_initial_population => 30 ~ preserve(parameter)

    N(N, P, b, a): prey_population        => b * N - a * N * P     ~ accumulate(init = N0)
    P(N, P, c, a, m): predator_population => c * a * N * P - m * P ~ accumulate(init = P0)
end

@system LotkaVolterra(PredatorPrey, Controller)
```

`N` and `P` appear in their own dependency lists. This recurrence is valid for
an accumulated state: the previous stored value participates in the rate used
for the next update. An ordinary `track` cycle would have no valid evaluation
order and would be rejected.

The `init` tags are explicit because zero populations would remain at the
trivial zero solution. The process omits `Controller` so it can be reused; the
runnable model adds the controller once.

## Configure and simulate

Use a daily update even though rates and plotted time are expressed per year.
Cropbox converts compatible units during accumulation.

```@example lotka
config = @config Clock => :step => 1u"d"

classic = simulate(LotkaVolterra;
    config,
    stop = 30u"yr",
    snap = 30u"d",
    index = :t,
    target = [:N, :P],
)

last(classic, 3)
```

```@example lotka
visualize(classic, :t, [:N, :P]; kind = :line)
```

The trajectories should be read together: prey growth supports a later
predator increase, which then suppresses prey and is followed by predator
decline. A time step that is too coarse can change the phase and amplitude, so
check numerical convergence before interpreting parameters biologically.

## Add density dependence with a mixin

A prey carrying capacity ``K`` changes the first equation to

```math
\frac{dN}{dt} = bN\left(1-\frac{N}{K}\right)-aNP.
```

Reuse the original process and replace only `N`:

```@example lotka
@system DensityDependent(PredatorPrey, Controller) begin
    K: prey_carrying_capacity => 1000 ~ preserve(parameter)

    N(N, P, K, b, a): prey_population =>
        b * N * (1 - N / K) - a * N * P ~ accumulate(init = N0)
end

bounded = simulate(DensityDependent;
    config,
    stop = 30u"yr",
    snap = 30u"d",
    index = :t,
    target = [:N, :P],
)

last(bounded, 3)
```

Because later declarations take precedence, the new `N` replaces the one from
`PredatorPrey`; the remaining parameters and predator equation are reused.
Compare the two models with the same time step, stop rule, initial
values, and output layout.

## Connect observations

The original tutorial used the historical Hudson Bay hare and lynx pelt series.
The source
[`pelts.csv`](https://github.com/cropbox/Cropbox.jl/blob/main/docs/src/tutorials/pelts.csv)
remains with this manual. `unitfy` reads the unit annotation in `Year (yr)` and
removes it from the column name.

Download [`pelts.csv`](pelts.csv) into your working directory before running
the following block. `pwd()` shows which directory Julia is using.

```@example lotka
pelts = CSV.read(
    "pelts.csv",
    DataFrame,
) |> unitfy

first(pelts, 3)
```

```@example lotka
visualize(pelts, :Year, [:Hare, :Lynx]; kind = :scatterline)
```

Pelt counts are an observation proxy rather than direct population censuses.
That distinction, the unknown scaling between series, and the time interval
chosen for fitting must be part of the model interpretation.

## Fit one interval and evaluate another

Use the annual counts from 1845–1904 for calibration and reserve 1905–1935 for
validation. Compute elapsed time **before** splitting the table: 1905 must be
year 60 of the same trajectory, not year zero of a new simulation.

```@example lotka
observations = transform(pelts, :Year => (y -> y .- first(y)) => :t)
calibration = observations[observations.Year .< 1905u"yr", :]
validation = observations[observations.Year .>= 1905u"yr", :]
(nrow(calibration), nrow(validation), first(validation.t))
```

Fit the prey birth rate `b` and predator mortality rate `m`; leave the other
four parameters unchanged. For these annual observations, use 52 equal steps
per year. Every whole-year observation then coincides with a clock tick.
The bounds use the rates' declared unit, `u"yr^-1"`.

```@example lotka
annual = @config config + (Clock => :step => (1//52)u"yr")
populations = [:Hare => :N, :Lynx => :P]

fitted = calibrate(LotkaVolterra, calibration;
    config = annual,
    index = :t,
    target = populations,
    parameters = PredatorPrey => (b = (0.35, 0.8), m = (0.35, 0.8)),
    stop = last(calibration.t),
    metric = :rmse,
    optim = (MaxSteps = 100, PopulationSize = 20, TraceMode = :silent),
)
```

Keep the fitted rates, initial populations, and clock unchanged. Run from 1845
through the last validation year; only the 31 later observations enter these
two RMSEs, one per species in the order given by `populations`:

```@example lotka
fitted_config = @config(annual + fitted)
scores = evaluate(LotkaVolterra, validation;
    config = fitted_config,
    index = :t,
    target = populations,
    stop = last(validation.t),
    metric = :rmse,
)
DataFrame(series = ["Hare", "Lynx"], validation_rmse = collect(scores))
```

These scores describe agreement with pelt counts, not accuracy against a
population census. To compare the density-dependent model, fit its rates (and
optionally `K`) on the same calibration years and score the same validation
years. See [Evaluate and Calibrate Models](@ref evaluation-tutorial) for
choosing bounds, comparing targets, and working with several environments.
