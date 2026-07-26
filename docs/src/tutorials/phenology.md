# [Build a Weather-driven Model](@id phenology-tutorial)

This tutorial develops a thermal-time model from an equation, connects it to
daily weather, and stops the simulation at maturity. It introduces the pattern
used by larger crop models: process components are written independently, then
composed with environment and controller systems.

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
using TimeZones

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
    Tb: base_temperature                      => 5                 ~ preserve(parameter, u"°C")
    Topt: optimum_temperature                 => 30                ~ preserve(parameter, u"°C")
    requirement                               => 75                ~ preserve(parameter, u"K*d")

    Tbounded(T, Topt)                         => T                 ~ track(max = Topt, u"°C")
    ΔT(Tbounded, Tb): effective_temperature   => Tbounded - Tb     ~ track(min = 0, u"K")
    TT(ΔT): thermal_time                                           ~ accumulate(u"K*d")
    mature(TT, requirement)                   => TT >= requirement ~ flag
end
```

The `max = Topt` tag caps the stored temperature and `min = 0` implements the
lower bound of effective temperature. The equation therefore contains no
hidden clamping function. `accumulate` combines effective temperature with the
daily clock step and stores kelvin-days.

## Compose and configure

```@example phenology
@system PhenologyModel(ThermalTime, Weather, Controller)

config = @config (
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 4, 1, tz"UTC"),
    Weather => :data => weather,
)
```

The final system contains the process, environment, and root controller. The
same `ThermalTime` component can be reused with another weather implementation.

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

For a CSV file with `date` and `Tavg` columns:

```julia
using CSV, DataFrames

weather = CSV.read("weather.csv", DataFrame)
weather.date = Date.(weather.date)
config = @config config + (Weather => :data => weather)
```

Before simulation, verify that dates are ordered, unique, and cover the entire
requested period. `provide` cannot invent missing weather observations.

## Extend the model

Useful next exercises are:

- add optimum and ceiling temperatures with a beta response;
- replace `mature` with several stage flags;
- use `remember(when=mature)` to capture the maturity date;
- compare simulated dates with observations using `evaluate`;
- calibrate `Tb` and `requirement` on training years, then evaluate held-out
  years.

The [Evaluation and Calibration](@ref evaluation-tutorial) tutorial covers the
last two steps.
