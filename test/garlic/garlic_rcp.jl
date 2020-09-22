include("garlic.jl")

using TimeZones
using Dates
using Interpolations: LinearInterpolation

KMSP = (
# # CV PHYL ILN GLN LL LER SG SD LTAR LTARa LIR Topt Tceil critPPD
# KM1 134 4 10 65.0 4.70 1.84 122 0 0.4421 0.1003 22.28 34.23 12
    :Phenology => (
        optimal_temperature = 22.28, # Topt
        ceiling_temperature = 34.23, # Tceil
        maximum_germination_rate = 0.45,
        maximum_emergence_rate = 0.2,
        critical_photoperiod = 12, # critPPD
        #initial_leaves_at_harvest = , # ILN
        maximum_leaf_initiation_rate = 0.1003, # LIR
        # storage_days = 100, # SD
        storage_temperature = 5,
        # maximum_leaf_tip_appearance_rate = 0, # LTAR (tracked)
        maximum_leaf_tip_appearance_rate_asymptote = 0.4421, # LTARa
        leaves_generic = 10, # GLN
    ),
    :Leaf => (
        maximum_elongation_rate = 4.70, # LER
        minimum_length_of_longest_leaf = 65.0, # LL
        # stay_green = , # SG
    ),
    :Carbon => (
# # Rm Yg
# 0.012 0.8
        maintenance_respiration_coefficient = 0.012, # Rm
        synthesis_efficiency = 0.8, # Yg
        partitioning_table = [
        # root shoot leaf sheath scape bulb
          0.00  0.00 0.00   0.00  0.00 0.00 ; # seed
          0.10  0.00 0.45   0.45  0.00 0.00 ; # vegetative
          0.10  0.00 0.15   0.25  0.10 0.40 ; # bulb growth with scape
          0.10  0.00 0.15   0.30  0.00 0.45 ; # bulb growth without scape
          0.00  0.00 0.00   0.00  0.00 0.00 ; # dead
        ],
    ),
)

ND = (KMSP,
    :Phenology => (;
        initial_leaves_at_harvest = 5, # ILN
        storage_days = 100, # SD
    ),
    :Leaf => (;
        minimum_length_of_longest_leaf = 50.0, # LL
        stay_green = 1.50, # SG
    ),
    :Plant => (;
        planting_density = 55.5, # PD
    ),
)

STATION_NAMES = Dict(
    165 => :Mokpo,
    185 => :Gosan,
    221 => :Jechun,
    261 => :Haenam,
    262 => :Goheung,
    263 => :Euryung,
    272 => :Youngju,
    295 => :Namhae,
    601 => :Danyang,
)

LATLONGS = Dict(
    165 => (; latitude = 34.81689, longitude = 126.38121),
    185 => (; latitude = 33.29382, longitude = 126.16283),
    221 => (; latitude = 37.15927, longitude = 128.1943),
    261 => (; latitude = 34.55375, longitude = 126.56907),
    262 => (; latitude = 34.61826, longitude = 127.27572),
    263 => (; latitude = 35.3226, longitude = 128.2881),
    272 => (; latitude = 36.87188, longitude = 128.51695),
    295 => (; latitude = 34.81662, longitude = 127.92641),
    601 => (; latitude = 36.98553, longitude = 128.3669),
)

rcp_co2(scenario, year) = begin
    x = [2005, 2050, 2100, 2150, 2250, 2300]
    y = if scenario == :RCP45
        [379, 487, 538, 543, 543, 543]
    elseif scenario == :RCP85
        [379, 541, 936, 1429, 1962, 1962]
    end
    LinearInterpolation(x, Float64.(y))(year)
end

rcp_config(; scenario, station, year, repetition, sowing_day, scape_removal_day) = begin
    name = "$(scenario)_$(station)_$(year)_$(repetition)"
    tz = tz"Asia/Seoul"
    start_date = ZonedDateTime(year, 9, 1, tz)
    end_date = ZonedDateTime(year+1, 6, 30, tz)

    date_from_doy(doy) = isnothing(doy) ? doy : ZonedDateTime(year, 1, 1, tz) + Dates.Day(doy - 1)
    planting_date = date_from_doy(sowing_day)
    scape_removal_date = date_from_doy(scape_removal_day)
    harvest_date = ZonedDateTime(year+1, 5, 15, tz)

    (ND,
        :Location => (;
            LATLONGS[station]...,
            altitude = 20.0,
        ),
        :Weather => (;
            filename = "$(@__DIR__)/data/RCP/$(name).wea",
            timezone = tz,
            CO2 = rcp_co2(scenario, year),
        ),
        :Calendar => (;
            init = start_date,
            last = end_date,
        ),
        :Phenology => (;
            planting_date,
            scape_removal_date,
            harvest_date,
        ),
        :Meta => (;
            scenario,
            station,
            year,
            repetition,
            sowing_day,
            scape_removal_day,
        )
    )
end

#setting = (; scenario=:RCP45, station=165, year=2021, repetition=1, sowing_day=250, scape_removal_day=nothing)

rcp_simulate(; target=:total_mass, setting) = begin
    #println((; setting...))
    config = rcp_config(; setting...)
    callback(s) = s.calendar.time' == s.config[:Phenology][:harvest_date]
    r = simulate(Garlic.Model; config, target, meta=:Meta, stop=callback, filter=callback, verbose=false)
end

settings = (;
    scenario = [:RCP45, :RCP85],
    station = keys(STATION_NAMES),
    year = 2020:10:2090,
    repetition = 1:10,
    sowing_day = 250:10:350, # 280:30:340
    scape_removal_day = [nothing],
)
rcp_run(; settings, verbose=true) = begin
    K = keys(settings)
    V = values(settings)
    P = Iterators.product(V...) |> collect
    n = length(P)
    R = Vector(undef, n)
    dt = verbose ? 1 : Inf
    p = Cropbox.Progress(n; dt, Cropbox.barglyphs)
    Threads.@threads for i in 1:n
        R[i] = rcp_simulate(; setting=zip(K, P[i]))
        Cropbox.ProgressMeter.next!(p)
    end
    Cropbox.ProgressMeter.finish!(p)
    reduce(vcat, R)
end
