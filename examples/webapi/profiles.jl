module WebAPIExamples

using Cropbox
using DataFrames
using Dates
using Garlic
using LeafGasExchange
using TimeZones

@system CherryBloomCF(Controller) begin
    "Daily weather table supplied as CSV or a DataFrame."
    weather        ~ provide(parameter)
    "Daily mean air temperature read from the tavg column."
    T: temperature ~ drive(from = weather, by = :tavg, u"°C")

    "Temperature threshold separating chilling and forcing."
    Tc: temperature_threshold => 10   ~ preserve(parameter, u"°C")
    "Accumulated chilling required before forcing begins."
    Rc: chilling_requirement  => -100 ~ preserve(parameter, u"K*d")
    "Accumulated forcing required for full bloom."
    Rf: forcing_requirement   => 100  ~ preserve(parameter, u"K*d")

    "Daily temperature difference from the threshold."
    ΔT(T, Tc): temperature_difference => T - Tc              ~ track(u"K")
    "Nonpositive daily chilling contribution."
    c(ΔT): chilling_unit              => ΔT                  ~ track(u"K", max = 0u"K")
    "Chilling accumulation until the requirement is met."
    C(c): chilling_accumulated        => c                   ~ accumulate(when = !d, u"K*d")
    "Whether the chilling requirement has been met."
    d(C, Rc): chilling_satisfied      => C <= Rc             ~ flag
    "Nonnegative daily forcing contribution."
    f(ΔT): forcing_unit               => ΔT                  ~ track(u"K", min = 0u"K")
    "Whether forcing can continue before full bloom."
    active(d, m)                      => d && !m             ~ flag
    "Forcing accumulation after chilling is satisfied."
    F(f): forcing_accumulated         => f                   ~ accumulate(when = active, u"K*d")
    "Whether the forcing requirement has been met."
    m(F, Rf): full_bloom              => F >= Rf             ~ flag
    "Fraction of the chilling requirement fulfilled."
    chill_progress(C, Rc)             => clamp(C / Rc, 0, 1) ~ track
    "Fraction of the forcing requirement fulfilled."
    bloom_progress(F, Rf)             => clamp(F / Rf, 0, 1) ~ track
end

"""
    cherry_profile()

Configure the daily chilling-forcing model with a fixed synthetic seasonal
temperature series. The weather is illustrative, not an observed bloom dataset.
Changing `Rc` and `Rf` illustrates unit-aware configuration and plot updates.
"""
function cherry_profile()
    temperatures = [round(14 + 11sin(2pi * ((mod(275 + i - 1, 365) + 1) - 110) / 365) +
                          1.4sin(2pi * i / 13); digits=2) for i in 0:242]
    weather = DataFrame(index=collect(0:242)u"d", tavg=temperatures * u"°C")
    config = @config(
        :Clock => :step => 1u"d",
        :CherryBloomCF => (; weather, Tc=10u"°C", Rc=-100u"K*d", Rf=100u"K*d"),
    )
    ui = Dict(
        "title" => "Cherry Bloom Dashboard",
        "stop" => Dict("value" => 242, "unit" => "d"),
        "outputs" => ["T", "ΔT", "C", "Rc", "F", "Rf", "d", "m", "chill_progress", "bloom_progress"],
        "panels" => [
            Dict("x" => "time", "y" => ["C", "F", "Rc", "Rf"], "kind" => "line",
                 "linestyles" => ["solid", "solid", "dash", "dash"]),
            Dict("x" => "time", "y" => ["T"], "kind" => "line"),
        ],
    )
    (; system=CherryBloomCF, config, ui,
       request_defaults=Dict{String,Any}("stop" => Dict("value" => 242, "unit" => "d")))
end

"""
    gasexchange_profile()

Configure the coupled C3 leaf model using the package's physiological parameters.
Two visualization presets vary atmospheric CO2 or air temperature. Component
paths and aliases remain selectable in the dashboard.
"""
function gasexchange_profile()
    config = @config(:Weather => (; PFD=1500, CO2=400, RH=60, T_air=25, wind=2.0))
    targets = ["Ac", "Aj", "Ap", "A_net"]
    ui = Dict(
        "title" => "Leaf Gas Exchange Dashboard",
        "stop" => Dict("value" => 1, "unit" => "hr"),
        "outputs" => [targets..., "gs", "Ci", "T", "PFD", "CO2", "T_air"],
        "panels" => [
            Dict("x" => "Ci", "y" => targets, "kind" => "line",
                 "xstep" => "Weather.CO2", "ymin" => 0, "ymax" => 70),
            Dict("x" => "T_air", "y" => targets, "kind" => "line",
                 "xstep" => "Weather.T_air", "ymin" => 0, "ymax" => 40),
        ],
        "sweeps" => [
            Dict("path" => "Weather.CO2", "label" => "Weather.CO2", "system" => "Weather",
                 "name" => "CO2", "start" => 10, "stop" => 1500, "step" => 10, "unit" => "μmol/mol"),
            Dict("path" => "Weather.T_air", "label" => "Weather.T_air", "system" => "Weather",
                 "name" => "T_air", "start" => 0, "stop" => 45, "step" => 1, "unit" => "°C"),
        ],
    )
    (; system=LeafGasExchange.ModelC3BB, config, ui,
       request_defaults=Dict{String,Any}("stop" => Dict("value" => 1, "unit" => "hr")))
end

"""
    garlic_profile()

Configure the whole-plant model from the package's KM, CUH and P2 presets.
The bundled, normalized CSV replaces `Weather.s`. Column metadata supplies
units and the time zone. Only the preparation script reads the original WEA.
"""
function garlic_profile()
    timezone = tz"America/Los_Angeles"
    weather_path = normpath(joinpath(@__DIR__, "../../test/examples/data/garlic/cuh_2014_weather.csv"))
    columns = [
        Dict("name" => "index", "type" => "ZonedDateTime", "timezone" => string(timezone)),
        Dict("name" => "SolRad", "type" => "Float64", "unit" => "W/m^2"),
        Dict("name" => "RH", "type" => "Float64", "unit" => "percent"),
        Dict("name" => "Tair", "type" => "Float64", "unit" => "°C"),
        Dict("name" => "Wind", "type" => "Float64", "unit" => "m/s"),
    ]
    config = @config(Garlic.Examples.AoB.KM, Garlic.Examples.AoB.CUH, Garlic.Examples.AoB.P2, (
        :Calendar => (init=ZonedDateTime(2014, 9, 1, 1, timezone), last=ZonedDateTime(2015, 7, 7, timezone)),
        :Meta => (year=2014,),
        :Phenology => (
            storage_days=143,
            planting_date=ZonedDateTime(2014, 11, 20, timezone),
            emergence_date=ZonedDateTime(2014, 12, 30, timezone),
            scape_removal_date=nothing,
        ),
    ))
    ui = Dict(
        "title" => "Garlic Crop Model Dashboard",
        "stop" => Dict("value" => "calendar.count", "unit" => ""),
        "outputs" => ["DAP", "leaves_appeared", "leaves_mature", "leaves_dropped",
                      "green_leaf_area", "leaf_mass", "bulb_mass", "scape_mass", "total_mass"],
        "panels" => [
            Dict("x" => "DAP", "y" => ["leaves_appeared", "leaves_mature", "leaves_dropped"], "kind" => "step"),
            Dict("x" => "DAP", "y" => ["leaf_mass", "bulb_mass", "scape_mass", "total_mass"], "kind" => "line"),
        ],
        "table_inputs" => [Dict("path" => "Weather.s", "label" => "Hourly weather",
                                "default_filename" => basename(weather_path), "columns" => columns)],
    )
    request_defaults = Dict{String,Any}(
        "stop" => "calendar.count",
        "snap" => (s -> Dates.hour(s.calendar.time') == 12),
        "config_entries" => [Dict("path" => "Weather.s", "value" => Dict(
            "type" => "CSV", "filename" => basename(weather_path),
            "content" => read(weather_path, String), "columns" => columns,
        ))],
    )
    (; system=Garlic.Model, config, ui, request_defaults)
end

"""Return a service profile for `cherry`, `gasexchange`, or `garlic`."""
function profile(name)
    name == "cherry" && return cherry_profile()
    name == "gasexchange" && return gasexchange_profile()
    name == "garlic" && return garlic_profile()
    throw(ArgumentError("choose cherry, gasexchange, or garlic"))
end

end
