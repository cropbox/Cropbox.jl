# [Weather-driven Phenology](@id phenology-tutorial)

This tutorial develops a thermal-time model from an equation, connects it to
daily weather, and stops the simulation at maturity. It then reuses the weather
component for a two-stage chilling–forcing model. Process components are written
independently, then composed with environment and controller systems.

Add the packages used below to your active Julia environment, then run the
blocks in order in the same session. `Dates` is part of Julia.

```julia
using Pkg
Pkg.add(["Cropbox", "DataFrames"])
```

## The model

For daily mean temperature ``T``, base temperature ``T_b``, and optimum
temperature ``T_{opt}``, define effective temperature and accumulated thermal
time as

```math
\Delta T = \max(\min(T, T_{opt}) - T_b, 0), \qquad
TT_{i+1} = TT_i + \Delta T_i \Delta t.
```

The crop is mature when ``TT`` reaches its requirement.

## Prepare weather data

The example is self-contained. A real analysis would normally read the same
columns from a CSV file. The Beltsville, Maryland 2002
[`weather.csv`](https://github.com/cropbox/Cropbox.jl/blob/main/docs/src/tutorials/weather.csv)
used by the original tutorial remains available as a larger unit-annotated
sample.

```@example phenology
using Cropbox
using DataFrames
using Dates

dates = Date(2025, 4, 1):Day(1):Date(2025, 4, 20)
weather = DataFrame(
    date = collect(dates),
    Tavg = [10, 11, 12, 14, 15, 16, 17, 16, 15, 14,
            13, 12, 14, 16, 18, 19, 17, 15, 13, 12],
)
```

Keep units at the model boundary. Here the table contains plain numbers and the
`drive` declaration supplies degrees Celsius.

## Declare the weather component

```@example phenology
@system Weather begin
    calendar(context)   ~ ::Calendar
    date(calendar.date) ~ track::date

    data           ~ provide(parameter, index = :date, init = date)
    T: temperature ~ drive(from = data, by = :Tavg, u"°C")
end
```

`provide` stores an indexed table. `drive` reads the row corresponding to the
current calendar date. The model equations depend on `T`, not on DataFrame
operations.

## Declare thermal time

```@example phenology
@system ThermalTime begin
    Tb: base_temperature      => 5  ~ preserve(parameter, u"°C")
    Topt: optimum_temperature => 30 ~ preserve(parameter, u"°C")
    requirement               => 75 ~ preserve(parameter, u"K*d")

    Tbounded(T, Topt)                           => T      ~ track(max = Topt, u"°C")
    ΔT(T = Tbounded, Tb): effective_temperature => T - Tb ~ track(min = 0, u"K")

    TT(ΔT): thermal_time                   ~ accumulate(u"K*d")
    mature(TT, R = requirement) => TT >= R ~ flag
end
```

The `max = Topt` tag caps the stored temperature and `min = 0` implements the
lower bound of effective temperature. The equation therefore contains no
hidden clamping function. `accumulate` combines effective temperature with the
daily clock step and stores kelvin-days.

`T = Tbounded` and `R = requirement` are local argument aliases; they shorten
the equations without renaming the model variables.

## Compose the executable model

```@example phenology
@system PhenologyModel(ThermalTime, Weather, Controller)
```

`visualize` with `kind = :hierarchy` shows how the reusable process,
environment, controller, and child systems are assembled:

```@example phenology
visualize(PhenologyModel; kind = :hierarchy)
```

Dashed arrows identify mixins; solid arrows identify child-system
relationships. The runtime context is omitted while the `Calendar` used by
`Weather` remains visible.

The final system contains the process, environment, and root controller. The
same `ThermalTime` component can be reused with another weather implementation.

## Follow weather into the thermal state

A mixed selection follows the input table into the thermal-state update and
includes the direct inputs to the maturity flag. Grouping by system separates
the weather and process declarations without changing the selection:

```@example phenology
g = visualize(PhenologyModel, [:data => :TT, :mature]; direction = :up)
Cropbox.writeimage("phenology-path.svg", g; style = (group = :system,))
nothing # hide
```

![Weather-to-thermal-state path and maturity inputs grouped by declaring system](phenology-path.svg)

The cylinder `data` provides the table, the parallelogram `T` reads a row,
the rectangles represent phases of the accumulated `TT`, and the diamond
`mature` tests the threshold. The gray boundaries name declaring mixins,
not separate runtime instances.

The post-update stage `⋆TT` stores the new rate for the next time advance;
the main stage `TT` integrates the stored rate and supplies `mature`.
There is no direct `data => mature` path in this generated scheduling
graph: that influence crosses a timestep boundary. The mixed selection shows
both parts without adding an artificial edge between them.

This selection omits off-path inputs such as `Tb` and `Topt`; it is not a
complete list of model inputs. Use `visualize(PhenologyModel)` for the full
graph, or `visualize(PhenologyModel, :mature; depth = 2, direction = :up)`
for its local upstream neighborhood. The graph is available before supplying
weather data or running the model; it does not show which dates satisfy the
maturity condition.

## Configure the scenario

```@example phenology
config = @config (
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 4, 1, tz"UTC"),
    Weather => :data => weather,
)
```

## Run to maturity

```@example phenology
result = simulate(PhenologyModel;
    config,
    stop = :mature,
    index = :date,
    target = [:T, :ΔT, :TT, :mature],
)
```

Inspect the last row rather than assuming maturity occurs exactly on the
requirement. A discrete daily model normally crosses the threshold.

```@example phenology
result[end, [:date, :TT, :mature]]
```

## Plot temperature and thermal time

```@example phenology
visualize(result, :date, :TT; kind = :line)
```

Plot variables with incompatible dimensions in separate panels. A shared axis
for temperature and thermal time would be visually convenient but physically
misleading.

## Compare base temperatures

```@example phenology
configs = @config config + !(ThermalTime => :Tb => [0, 5, 10])

comparison = simulate(PhenologyModel;
    configs,
    stop = :mature,
    index = :date,
    target = [:TT, :mature],
    meta = :ThermalTime,
)
```

Each configuration creates a fresh model. The metadata column records the base
temperature used in each run.

## Chilling and forcing

Some phenology models distinguish a cold requirement from subsequent warmth.
The example below adapts the simplified daily-mean model from the
[Cropbox Taiwan workshop](https://github.com/cropbox/cropbox-workshop-2022-tw/blob/main/4-Phenology.ipynb).
It is not the full minimum/maximum-temperature formulation also shown there.

First clamp temperature at zero degrees Celsius, then subtract a threshold
``T_c``. The negative part supplies chilling and the positive part supplies
forcing:

```math
\begin{aligned}
T_a &= \max(T, 0^{\circ}\mathrm{C}), & \Delta T &= T_a - T_c, \\
c &= \min(\Delta T, 0\,\mathrm{K}), & f &= \max(\Delta T, 0\,\mathrm{K}).
\end{aligned}
```

Chilling accumulates until ``C \leq R_c``. Only then does forcing accumulate,
with bloom reached when ``F \geq R_f``. Chilling is **negative** in this model:
``C`` decreases toward a negative requirement, while ``F`` increases toward a
positive requirement. Both accumulated quantities have units of kelvin-days,
not chilling hours.

### Declare the two stages

```@example phenology
@system ChillForce begin
    Tc: temperature_threshold => 10   ~ preserve(parameter, u"°C")
    Rc: chilling_requirement  => -100 ~ preserve(parameter, u"K*d")
    Rf: forcing_requirement   => 100  ~ preserve(parameter, u"K*d")

    Ta(T)                 ~ track(min = 0, u"°C")
    ΔT(Ta, Tc) => Ta - Tc ~ track(u"K")

    c(ΔT): chilling                    ~ track(max = 0, u"K")
    C(c): chilling_accumulated         ~ accumulate(when = !d, u"K*d")
    d(C, Rc): chilling_done => C <= Rc ~ flag

    f(ΔT): forcing                     ~ track(min = 0, u"K")
    F(f): forcing_accumulated          ~ accumulate(when = d, u"K*d")
    bloom(F, Rf)           => F >= Rf  ~ flag

    stop(bloom, last = calendar.stop) => bloom || last ~ flag
end

@system ChillForceModel(ChillForce, Weather, Controller)
```

`when` controls the rate supplied to each accumulator. Once `d` becomes true,
`C` keeps its accumulated value and `F` starts accumulating. The flag does not
need `once` here: chilling cannot increase, so the threshold remains satisfied.
The `stop` flag also checks the end of the available weather; reaching that
date does not imply that bloom occurred.

### Configure a winter-to-spring scenario

This synthetic 90-day series combines seasonal warming with weekly variation.
The temperatures and parameter values illustrate the two stages; they are not
observations or calibrated predictions for a particular species or site.

```@example phenology
t = 0:89
winter = DataFrame(
    date = Date(2025, 1, 1) .+ Day.(t),
    Tavg = 9 .- 9cos.(π .* t ./ last(t)) .+ 2sin.(2π .* t ./ 7),
);

cf_config = @config config + (
    Calendar => (;
        init = ZonedDateTime(DateTime(first(winter.date)), tz"UTC"),
        last = ZonedDateTime(DateTime(last(winter.date)), tz"UTC"),
    ),
    Weather => :data => winter,
)
nothing # hide
```

The daily clock step is inherited from `config`. Simulate once and use the
returned DataFrame for all three plots. Both accumulators start at zero on the
calendar's initial date:

```@example phenology
cf = simulate(ChillForceModel;
    config = cf_config, stop = :stop, index = :date,
    target = [:T, :Ta, :Tc, :c, :f, :C, :F, :Rc, :Rf, :d, :bloom])
nothing # hide
```

### Inspect the responses and accumulated amounts

The clamped temperature `Ta` cannot fall below zero. The dashed line marks the
threshold separating the chilling and forcing responses.

```@example phenology
visualize(cf, :date, [:T, :Ta, :Tc];
    kind = :line, linestyle = [:solid, :dot, :dash],
    names = ["Temperature", "Clamped temperature", "Threshold"],
    ylab = "Temperature")
```

The daily responses have units of kelvin. A positive forcing response alone is
not enough to increase `F`: the chilling requirement must also have been met.

```@example phenology
visualize(cf, :date, [:c, :f];
    kind = :line, names = ["Chilling", "Forcing"], ylab = "Daily response")
```

Plot both accumulated amounts and their requirements on one axis because they
share the same units. Solid curves show the simulated states; dashed lines
show the requirements.

```@example phenology
visualize(cf, :date, [:C, :F, :Rc, :Rf];
    kind = :line, linestyle = [:solid, :solid, :dash, :dash],
    names = ["Chilling", "Forcing", "Chilling requirement", "Forcing requirement"],
    ylab = "Accumulation")
```

The daily step can carry an accumulated amount beyond its requirement. Inspect
the first row with completed chilling and the final row, including the bloom
flag, rather than treating a threshold as an exact final value:

```@example phenology
cf[[findfirst(cf.d), nrow(cf)], [:date, :C, :F, :d, :bloom]]
```

If a different configuration never meets the chilling requirement, `d` stays
false and `F` stays zero. If either stage is unfinished at the last weather
date, the final `bloom` flag is false; that date must not be used as a predicted
bloom date. The `findfirst(cf.d)` row selection above assumes chilling was
completed, as it is in this example.

## Replace synthetic data

For your own CSV file with plain `date` and `Tavg` headers, add `CSV` first:

```julia
using Pkg
Pkg.add("CSV")
```

```julia
using CSV, DataFrames

weather = CSV.read("my-weather.csv", DataFrame)
weather.date = Date.(weather.date)
config = @config config + (
    Calendar => :init => ZonedDateTime(DateTime(first(weather.date)), tz"UTC"),
    Weather => :data => weather,
)
```

Before simulation, verify that dates are ordered, unique, and cover the entire
requested period. `provide` cannot invent missing weather observations.
For `ChillForceModel`, replace the weather table and both calendar endpoints in
`cf_config`; the starting date determines which cold period is accumulated.
The older Beltsville sample linked above has annotated headers such as
`Tavg (°C)` and `date (:Date)`; use `unitfy` after reading that file to normalize
its column names, units, and date types before configuring the model.

## Extend the model

Useful next exercises are:

- add optimum and ceiling temperatures with a beta response;
- replace `mature` with several stage flags;
- use `remember(when=mature)` to capture the maturity date;
- compare simulated dates with observations using `evaluate`;
- calibrate `Tb` and `requirement` on some years, then use other years for
  validation.

For the chilling–forcing model, the corresponding calibration parameters are
`Tc`, `Rc`, and `Rf`. Keep the simulation's starting date consistent between
calibration and validation.

The [Evaluate and Calibrate Models](@ref evaluation-tutorial) workflow covers the
last two steps.
