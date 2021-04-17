include("garlic.jl")

using TimeZones
using Dates
using Interpolations: LinearInterpolation
using BSON

tz = tz"Asia/Seoul"

date(year, month::Int, day::Int; tz=tz) = ZonedDateTime(year, month, day, tz)
date(year, doy::Int; tz=tz) = ZonedDateTime(year, 1, 1, tz) + Dates.Day(doy - 1)
date(year, d::ZonedDateTime; tz=tz) = d
date(year, d::DateTime; tz=tz) = ZonedDateTime(d, tz)
date(year, ::Nothing; tz=tz) = nothing

storagedays(t::ZonedDateTime) = (t - ZonedDateTime(year(t), 6, 30, timezone(t))) |> Day |> Dates.value

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
        maximum_leaf_tip_appearance_rate_asymptote = 0.60, # LTARa
    ),
    :Leaf => (;
        #minimum_length_of_longest_leaf = 65.0, # LL
        stay_green = 1.80, # SG
    ),
    :Plant => (;
        initial_planting_density = 55.5, # PD0
    ),
    :Carbon => (
        partitioning_table = [
        # root shoot leaf sheath scape bulb
          0.00  0.00 0.00   0.00  0.00 0.00 ; # seed
          0.45  0.00 0.25   0.25  0.00 0.05 ; # vegetative
          0.20  0.00 0.10   0.05  0.20 0.45 ; # bulb growth with scape
          0.10  0.00 0.00   0.00  0.00 0.90 ; # bulb growth without scape
          0.00  0.00 0.00   0.00  0.00 0.00 ; # dead
        ],
    )
)

GL = (
    :Location => (; latitude = 37.1288422, longitude = 128.3628756),
    :Plant => (; initial_planting_density = 55.5),
)
GL_2012 = (GL,
    :Weather => (
        store = Garlic.loadwea("$(@__DIR__)/data/Korea/garliclab_2012.wea", tz),
    ),
    :Calendar => (
        init = date(2012, 10, 1),
        last = date(2013, 6, 30),
    ),
)
ND_GL_2012 = let planting_date = date(2012, 10, 4)
    (
        ND, GL_2012,
        :Phenology => (;
            planting_date,
            scape_removal_date = nothing,
            harvest_date = date(2013, 6, 15),
            storage_days = storagedays(planting_date),
        )
    )
end

JS = (
    :Location => (; latitude = 33.46835535536083, longitude = 126.51765156091567),
    :Plant => (; initial_planting_density = 55.5),
)
JS_2009 = (JS,
    :Weather => (
        store = Garlic.loadwea("$(@__DIR__)/data/Korea/jungsil_2009.wea", tz),
    ),
    :Calendar => (
        init = date(2009, 9, 1),
        last = date(2010, 6, 30),
    ),
)
ND_JS_2009 = let planting_date = date(2009, 9, 15)
    (
        ND, JS_2009,
        :Phenology => (;
            planting_date,
            scape_removal_date = nothing,
            harvest_date = date(2010, 6, 18),
            storage_days = storagedays(planting_date),
        )
    )
end

STATION_NAMES = Dict(
    101 => :Chuncheon,
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
    101 => (; latitude = 37.90262, longitude = 127.7357),
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

rcp_config(; config=(), tz=tz, kw...) = _rcp_config(; config, meta=kw, tz, kw...)
_rcp_config(; config=(), meta=(), tz=tz, scenario, station, year, repetition, sowing_day, scape_removal_day) = begin
    latlongs = LATLONGS[station]
    name = "$(scenario)_$(station)_$(year)_$(repetition)"
    weaname = "$(@__DIR__)/data/RCP/$name.wea"
    CO2 = rcp_co2(scenario, year)
    garlic_config(; config, meta, tz, latlongs..., weaname, CO2, year, sowing_day, scape_removal_day)
end

garlic_config(; config=(), meta=(), tz=tz, latitude, longitude, altitude=20, weaname, CO2=390, year, sowing_day, scape_removal_day) = begin
    start_date = date(year, 9, 1)
    end_date = date(year+1, 6, 30)

    planting_date = date(year, sowing_day)
    scape_removal_date = date(year, scape_removal_day)
    harvest_date = date(year+1, 5, 15)
    storage_days = storagedays(planting_date)

    @config (ND,
        :Location => (;
            latitude,
            longitude,
            altitude,
        ),
        :Weather => (;
            store = Garlic.loadwea(weaname, tz),
            CO2,
        ),
        :Calendar => (;
            init = start_date,
            last = end_date,
        ),
        :Phenology => (;
            planting_date,
            scape_removal_date,
            harvest_date,
            storage_days,
        ),
        :Meta => meta,
        config,
    )
end

#setting = (; scenario=:RCP45, station=165, year=2021, repetition=1, sowing_day=250, scape_removal_day=nothing)

garlic_simulate(; config, target) = begin
    callback(s) = s.calendar.time' == s.config[:Phenology][:harvest_date]
    simulate(Garlic.Model; config, target, meta=:Meta, stop=callback, snap=callback, verbose=false)
end

rcp_settings = (;
    scenario = [:RCP45, :RCP85],
    station = keys(STATION_NAMES),
    year = 2020:10:2090,
    repetition = 0:9,
    sowing_day = 240:10:350,
    scape_removal_day = [1],
)
rcp_run(; configurator=rcp_config, settings=rcp_settings, kw...) = garlic_run(; configurator, settings, kw...)

garlic_compose(; config=(), configurator, settings) = begin
    K = keys(settings)
    V = values(settings)
    P = Iterators.product(V...) |> collect
    [configurator(; config, zip(K, p)...) for p in P]
end

garlic_run(;
    target=[:bulb_mass, :total_mass, :planting_density, :yield, :leaf_area],
    config=(),
    configurator,
    settings,
    cache=nothing,
    verbose=true,
) = begin
    C = garlic_compose(; config, configurator, settings)
    n = length(C)
    R = isnothing(cache) ? Vector(undef, n) : cache
    @assert length(R) == n
    dt = verbose ? 1 : Inf
    p = Cropbox.Progress(n; dt, Cropbox.barglyphs)
    try
        Threads.@threads for i in 1:n
            config = C[i]
            !isassigned(R, i) && (R[i] = garlic_simulate(; config, target))
            Cropbox.ProgressMeter.next!(p)
        end
    catch
        return R
    end
    Cropbox.ProgressMeter.finish!(p)
    reduce(vcat, R)
end

garlic_run_storage(; configurator, settings, name, kw...) = begin
    c0 = :Meta => :storage => true
    c1 = (
        :Phenology => :storage_days => 100,
        :Meta => :storage => false,
    )
    r0 = garlic_run(; configurator, settings, config=c0)
    bson("garlic_$name-storage-on.bson", df = r0)
    r1 = garlic_run(; configurator, settings, config=c1)
    bson("garlic_$name-storage-off.bson", df = r1)
    r = [r0; r1]
    bson("garlic_$name-storage.bson", df = r)
end

garlic_run_cold(; configurator, settings, name, kw...) = begin
    c0 = :Meta => :cold => true
    c1 = (
        :Density => :enable_cold_damage => false,
        :LeafColdInjury => :_enable => false,
        :Meta => :cold => false,
    )
    r0 = garlic_run(; configurator, settings, config=c0)
    bson("garlic_$name-cold-on.bson", df = r0)
    r1 = garlic_run(; configurator, settings, config=c1)
    bson("garlic_$name-cold-off.bson", df = r1)
    r = [r0; r1]
    bson("garlic_$name-cold.bson", df = r)
end
