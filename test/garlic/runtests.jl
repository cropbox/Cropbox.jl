using Cropbox
using Test

include("garlic.jl")

using TimeZones

ND = (
    :Calendar => (
        :init => ZonedDateTime(2007, 9, 1, tz"Asia/Seoul"),
        :last => ZonedDateTime(2008, 8, 31, tz"Asia/Seoul"),
    ),
    :Weather => (:store => Garlic.loadwea("$(@__DIR__)/data/2007.wea", tz"Asia/Seoul")),
    :Phenology => (:planting_date => ZonedDateTime(2007, 11, 1, tz"Asia/Seoul")),
)

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
KM = (KMSP, (
    :Phenology => (initial_leaves_at_harvest = 4,), # ILN
    :Leaf => (stay_green = 1.84,), # SG
))
SP = (KMSP, (
    :Phenology => (initial_leaves_at_harvest = 6,), # ILN
    :Leaf => (stay_green = 1.47,), # SG
))

CUH = (
# # LAT LONG ALT
# 47.66 122.29 20.0
    :Location => (
        latitude = 47.66, # LAT
        longitude = 122.29, #LONG
        altitude = 20.0, # ALT
    ),
# # CO2 timestep
# 390 60
    :Weather => (
        CO2 = 390, # CO2
    ),
    :Plant => (initial_planting_density = 55,), # PD0
)
CUH_2013 = (CUH, (
    :Weather => (
        store = Garlic.loadwea("$(@__DIR__)/data/CUH/2013.wea", tz"America/Los_Angeles"),
    ),
    :Calendar => (
        init = ZonedDateTime(2013, 10, 30, tz"America/Los_Angeles"), # Y1 bgn
        last = ZonedDateTime(2014, 7, 28, tz"America/Los_Angeles"), #Y2 end
    ),
))
CUH_2014 = (CUH, (
    :Weather => (
        store = Garlic.loadwea("$(@__DIR__)/data/CUH/2014.wea", tz"America/Los_Angeles"),
    ),
    :Calendar => (
        # 2014.wea starts from 2014-09-01 01:00, not 00:00
        init = ZonedDateTime(2014, 9, 1, 1, tz"America/Los_Angeles"), # Y1 bgn
        last = ZonedDateTime(2015, 7, 7, tz"America/Los_Angeles"), #Y2 end
    ),
))

CUH_2013_P1 = (CUH_2013, (
    :Phenology => (
        storage_days = 122, # SD
        planting_date = ZonedDateTime(2013, 10, 30, tz"America/Los_Angeles"), # Y1 sow
    ),
))
CUH_2013_P2 = (CUH_2013, (
    :Phenology => (
        storage_days = 170, # SD
        planting_date = ZonedDateTime(2013, 12, 17, tz"America/Los_Angeles"), # Y1 sow
    ),
))
CUH_2014_P1 = (CUH_2014, (
    :Phenology => (
        storage_days = 93, # SD
        planting_date = ZonedDateTime(2014, 10, 1, tz"America/Los_Angeles"), # Y1 sow
    ),
))
CUH_2014_P2 = (CUH_2014, (
    :Phenology => (
        storage_days = 143, # SD
        planting_date = ZonedDateTime(2014, 11, 20, tz"America/Los_Angeles"), # Y1 sow
    ),
))

KM_2013_P1_SR0 = (KM, CUH_2013_P1, (
    :Phenology => (
        emergence_date = ZonedDateTime(2013, 12, 29, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
KM_2013_P2_SR0 = (KM, CUH_2013_P2, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 1, 26, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
KM_2014_P1_SR0 = (KM, CUH_2014_P1, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 10, 26, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
KM_2014_P2_SR0 = (KM, CUH_2014_P2, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 12, 30, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))

SP_2013_P1_SR0 = (SP, CUH_2013_P1, (
    :Phenology => (
        emergence_date = ZonedDateTime(2013, 11, 14, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
SP_2013_P2_SR0 = (SP, CUH_2013_P2, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 1, 6, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
SP_2014_P1_SR0 = (SP, CUH_2014_P1, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 10, 6, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))
SP_2014_P2_SR0 = (SP, CUH_2014_P2, (
    :Phenology => (
        emergence_date = ZonedDateTime(2014, 11, 30, tz"America/Los_Angeles"), # Y1 emg
        scape_removal_date = nothing, # Y2 SR
    ),
))

using CSV
using DataFrames
using DataFramesMeta
import Dates
loaddata(cv, y, p) = begin
    ps = CSV.File("$(@__DIR__)/data/CUH/PhenologySummary.csv") |> DataFrame |> unitfy
    @linq ps |> where(:CV .== cv, :Year .== y, :Pgroup .== p) |> select(:DAP, :Leaves)
end

calibrate_LTAR(cv, y, p) = begin
    c = eval(Symbol("$(cv)_$(y)_P$(p)_SR0")) #HACK for now
    obs = loaddata(cv, y, p)
    f(s) = s.DAP' in obs.DAP && Dates.hour(s.calendar.time') == 12
    #r = simulate(Garlic.Model;
    calibrate(Garlic.Model, obs;
        config=c,
        stop="calendar.count",
        index=:DAP,
        target=:Leaves => :leaves_appeared,
        parameters=:Phenology => :LTAR_max => (0.01, 0.80),
        snap=f,
        optim=(:MaxSteps => 100,),
    )
end
#calibrate_LTAR("KM", 2014, 2)

@testset "garlic" begin
    r = simulate(Garlic.Model;
        config=KM_2014_P2_SR0,
        stop="calendar.count",
        snap=s -> Dates.hour(s.calendar.time') == 12,
    )
    @test r.leaves_initiated[end] > 0
    Cropbox.plot(r, :DAP, [:leaves_appeared, :leaves_mature, :leaves_dropped]) |> display # Fig. 3.D
    Cropbox.plot(r, :DAP, :green_leaf_area) |> display # Fig. 4.D
    Cropbox.plot(r, :DAP, [:leaf_mass, :bulb_mass, :total_mass]) |> display
end
