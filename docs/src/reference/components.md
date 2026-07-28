# [Built-in Model Components](@id built-in-components)

Cropbox exports a few reusable systems in addition to the framework itself.
They are mixins or child components, not complete crop models. Add them to a
root system with `Controller`, and replace or connect their input declarations
as needed.

## Temperature response components

`GrowingDegree`, `BetaFunction`, and `Q10Function` share a temperature input
named `T` and an elapsed step `Δt`. Their output `ΔT` is converted to a rate `r`
by dividing by `Δt`.

### `GrowingDegree`

`GrowingDegree` calculates thermal magnitude above a base temperature:

```math
\Delta T = \max(0, T' - T_b)
```

Here ``T'`` is first capped at optional optimum temperature `To`. Cropbox then
compares that capped value with optional maximum temperature `Tx`; a value at
or above `Tx` contributes zero. The public parameters are:

| Name | Meaning | Unit/default |
|---|---|---|
| `Tb` | base temperature | required, °C |
| `To` | optimum/capping temperature | optional, °C |
| `Tx` | temperature at or above which contribution is zero | optional, °C |

This order matters when both optional values are present. If `To < Tx`, the
cap prevents the following `Tx` condition from being reached. Use only the
threshold needed by the model, or test the combined response over the full
temperature range before adopting both.

The component is a rate response; accumulate `ΔT` or use `r` in a larger
phenology system according to that system's time convention. The weather-driven
tutorial shows a simpler explicit thermal-time declaration when the full
component is unnecessary.

### `BetaFunction`

`BetaFunction` returns a normalized, asymmetric temperature response. It is
zero outside `(Tn, Tx)`, equals one at `To`, and uses `β` to control shape.

| Name | Meaning | Default |
|---|---|---:|
| `Tn` | minimum temperature | `0u"°C"` |
| `To` | optimum temperature | required |
| `Tx` | maximum temperature | required |
| `β` | high-temperature shape coefficient | `1` |

The ordering `Tn < To < Tx` must hold. If it does not, the current component
returns zero rather than raising an error, so validate parameter sets before a
large simulation.

### `Q10Function`

`Q10Function` calculates:

```math
Q_{10}^{(T - T_o) / 10\,\mathrm{K}}
```

`To` is the reference temperature and `Q10` defaults to two. The result is a
relative multiplier, despite sharing the generic `ThermalTime` variable names.
Use it to scale a separately declared process rate; do not treat it as
accumulated thermal time.

### Compose a response

The components leave `T` as an override point so a model can connect its own
weather variable:

```julia
@system DevelopmentRate(GrowingDegree) begin
    T(weather.temperature) ~ track(u"°C")
end

@system DevelopmentModel(Weather, DevelopmentRate, Controller)
```

Check the merged declaration with `look(DevelopmentModel, :T)` because a later
mixin or local declaration can replace an earlier connection.

## Tabular input stores

The store systems expose the current row as `s`, so model declarations can
track columns from it:

```julia
@system WeatherInput(DateStore, Controller) begin
    TMAX(s) => s.TMAX ~ track(u"°C")
    TMIN(s) => s.TMIN ~ track(u"°C")
end
```

All CSV-backed stores call `unitfy` on column names. For example:

```csv
date (:Date),TMAX (°C),TMIN (°C)
2025-04-01,20,8
2025-04-02,22,9
```

Configure parameters on the executable root type when the store is mixed into
that root:

```julia
config = @config (
    WeatherInput => :filename => "weather.csv",
    Clock => :step => 1u"d",
    Calendar => :init => ZonedDateTime(2025, 4, 1, tz"UTC"),
)
```

### Store selection

| Component | Index used at runtime | Main inputs |
|---|---|---|
| `DataFrameStore` | generated row number stored under `ik` | `filename` or `df`, `ik` |
| `DayStore` | elapsed whole days | `daykey` (default `:day`) |
| `DateStore` | calendar date | `datekey` (default `:date`) |
| `TimeStore` | zoned date and time | `datekey`, `timekey`, `tz` |
| `TableStore` | row number | `filename` or typed table `tb` |

`DataFrameStore` accepts an in-memory DataFrame through its `df` parameter, so
file I/O is optional. `TableStore` does the same for a TypedTables table through
`tb`. These are construction inputs; changing the original object after
construction is not a supported way to drive a running model.

The base `DataFrameStore` numbers rows starting at one, writes those numbers to
the column selected by `ik` (default `:index`), and looks up the current row by
that generated key. It therefore replaces an existing column with the same
name; it does not use an arbitrary pre-existing `ik` column as a scientific
index. Use `DayStore`, `DateStore`, or `TimeStore` when the input already has a
meaningful elapsed-day or calendar key. `TableStore` is likewise row-ordered.

`DayStore` expects an integer-compatible day column and is appropriate when
elapsed day is the real key. `DateStore` uses `Calendar`, so it is safer for
weather keyed by civil dates. `TimeStore` combines date and time columns with a
configured time zone. Repeated local clock times during the daylight-saving
fall transition are interpreted in row order; use explicit, sorted input and
test the transition when subdaily timing matters.

The current row lookup requires a matching key. Missing dates, duplicate keys,
an inconsistent `Clock.step`, or an incorrect time zone usually surfaces as a
lookup error. Validate the input index before running the scientific model.

## Time infrastructure

The most frequently used exported infrastructure systems are:

| System | Role |
|---|---|
| `Controller` | creates the root configuration and context |
| `Context` | carries the normalized configuration and shared clock |
| `Clock` | tracks elapsed time, step, initialization, and tick |
| `Calendar` | maps clock time to `ZonedDateTime` and `Date` |

`Controller` belongs on the executable root. It normalizes the supplied
configuration and constructs one `Context`; nested systems receive that same
context from their parent. `Context` in turn constructs the configured `Clock`.
This is why ordinary components should not add their own controller or clock.

`Clock` exposes two parameters and two changing values:

| Name | Meaning | Default |
|---|---|---|
| `init` | elapsed time at construction | `0u"hr"` |
| `step` | duration of one model update | `1u"hr"` |
| `time` | current elapsed time | starts at `init` |
| `tick` | number of completed update advances | starts at `0` |

The default clock unit is hours. A plain configured number therefore means
hours; write an explicit quantity such as `1u"d"` when another unit is
intended. Both `time` and `tick` advance once per update. Output `snap` rules
only select states after this update schedule has been defined.

`Calendar` is not included in `Context` automatically. Add it as a child or
mixin when a model needs civil time:

| Name | Meaning |
|---|---|
| `init` | required starting `ZonedDateTime` |
| `last` | optional ending `ZonedDateTime` |
| `time` | `init` plus the elapsed clock time |
| `date` | `Date(time)` |
| `stop` | whether `time` has reached `last`; always false without `last` |
| `count` | rounded update count from `init` to `last`; `nothing` without `last` |

Configure compatible `Clock.step`, `Calendar.init`, and `Calendar.last` values
when `count` is used as a stopping condition. A duration that is not an exact
multiple of the step makes the rounding convention part of the experiment;
prefer an explicit Boolean or duration stop when that ambiguity matters.

These systems are introduced under [Systems and Composition](@ref system) and
followed through construction under [Model Execution](@ref model-execution).
`Date`, `Dates`, `ZonedDateTime`, and the `tz"..."` macro are re-exported for
convenience, as is Unitful's `u"..."` macro. They keep their behavior from their
source packages; Cropbox does not define a separate date or unit syntax.
