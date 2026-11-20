# [Weather-driven Phenology](@id phenology-tutorial)

This tutorial develops a thermal-time model from an equation, connects it to
daily weather, and stops at maturity. By the end you can read the maturity date,
compare base temperatures, and substitute your own daily weather.

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

    data                ~ provide(parameter, index = :date, init = date)
    T: temperature      ~ drive(from = data, by = :Tavg, u"°C")
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

    Tbounded(T, Topt)                       => T             ~ track(max = Topt, u"°C")
    ΔT(Tbounded, Tb): effective_temperature => Tbounded - Tb ~ track(min = 0, u"K")

    TT(ΔT): thermal_time                   ~ accumulate(u"K*d")
    mature(TT, R = requirement) => TT >= R ~ flag
end
```

The `max = Topt` tag caps the stored temperature and `min = 0` implements the
lower bound of effective temperature. The equation therefore contains no
hidden clamping function. `accumulate` combines effective temperature with the
daily clock step and stores kelvin-days.

`R = requirement` is a local argument alias; it shortens the maturity equation
without renaming the model variable.

## Compose the executable model

```@example phenology
@system PhenologyModel(ThermalTime, Weather, Controller)
```

To run the model now, jump to [Configure the scenario](#Configure-the-scenario).
The following structure plots are optional and were added after Cropbox v0.4.2.

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

A variable path follows the input table through the accumulated thermal state
to the maturity flag. Grouping by system separates the weather and process
declarations without changing the selection:

```@example phenology
g = visualize(PhenologyModel, :data => :mature; style = (group = :system,))
```

The cylinder `data` provides the table, the parallelogram `T` reads a row,
the rectangles represent phases of the accumulated `TT`, and the diamond
`mature` tests the threshold. The gray boundaries name declaring mixins,
not separate runtime instances.

The post-update stage `⋆TT` stores the new rate for the next time advance;
the main stage `TT` integrates the stored rate and supplies `mature`.
The path selector treats both stages as one variable when following influence,
but the picture retains the original scheduling edges. The selected path can
therefore span timesteps; it is not a same-timestep execution chain or an
additional edge from `⋆TT` back to `TT`.

This selection omits off-path inputs such as `Tb`, `Topt`, and `requirement`;
it is not a complete list of model inputs. Use `visualize(PhenologyModel)` for the full
graph, or `visualize(PhenologyModel, :mature; depth = 2, direction = :up)`
for its local upstream neighborhood. The graph is available before supplying
weather data or running the model; it does not show which dates satisfy the
maturity condition.

The same selection can be read vertically as one generated update:

```@example phenology
visualize(PhenologyModel, :T => :mature; kind = :flow)
```

The flow diagram separates `TT`'s value update from its rate-caching operation.
The fading ends of the side rails show continuation into the next update without
repeating the whole diagram. Inputs outside the selected path remain gray boundary lanes.
These are static potential reads, not a trace of which dates or branches ran;
see [the flow guide](@ref visualization-flow) for symbols and scope.

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
The older Beltsville sample linked above has annotated headers such as
`Tavg (°C)` and `date (:Date)`; use `unitfy` after reading that file to normalize
its column names, units, and date types before configuring the model.

## Extend the model

Useful next exercises are:

- add optimum and ceiling temperatures with a beta response;
- replace `mature` with several stage flags;
- use `remember(when = mature)` to capture the maturity date;
- compare simulated dates with observations using `evaluate`;
- calibrate `Tb` and `requirement` on some years, then use other years for
  validation.

The [Evaluate and Calibrate Models](@ref evaluation-tutorial) workflow covers the
last two steps.

Next in the learning path: [Predator–Prey Model](@ref lotka-volterra-tutorial),
where two changing states depend on one another.

## Chilling and forcing

For an optional second phenology model, follow [Chilling and Forcing](@ref
chilling-forcing-tutorial). It reuses the same weather component but counts
warmth toward bloom only after a cold requirement is met.
