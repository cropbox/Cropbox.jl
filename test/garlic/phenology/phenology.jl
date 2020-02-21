include("stage.jl")
include("germination.jl")
include("emergence.jl")
include("floralinitiation.jl")
include("leafinitiation.jl")
include("leafappearance.jl")
include("bulbappearance.jl")
include("scapegrowth.jl")
include("death.jl")

import Dates

#TODO make a common class to be shared by Garlic and MAIZSIM
@system Phenology(
    Germination,
    Emergence,
    FloralInitiation,
    LeafInitiation,
    LeafAppearance,
    BulbAppearance,
    ScapeGrowth,
    ScapeAppearance,
    ScapeRemoval,
    FlowerAppearance,
    BulbilAppearance,
    Death
) begin
    weather ~ ::Weather(override)
    sun ~ ::Sun(override)
    soil ~ ::Soil(override)

    planting_date ~ preserve::ZonedDateTime(parameter)
    DAP(t0=planting_date, t=context.calendar.time): day_after_planting => begin
        Δt = floor(t - t0, Dates.Day) |> Dates.value
        max(Δt, 0)
    end ~ track::Int

    leaves_generic => 10 ~ preserve::Int(parameter)
    leaves_potential(leaves_generic, leaves_total) => max(leaves_generic, leaves_total) ~ track::Int
    leaves_total(leaves_initiated) ~ track::Int

    T(leaves_appeared, T_air=weather.T_air): temperature => begin
        if leaves_appeared < 9
            #FIXME soil module is not implemented yet
            #T = T_soil
            #HACK garlic model does not use soil temperature
            T = T_air
        else
            T = T_air
        end
        #FIXME T_cur doesn't go below zero, but is it fair assumption?
        #max(T, 0.0u"°C")
    end ~ track(u"°C")
    #growing_temperature(r="gst_recorder.rate") => r ~ track
    T_opt: optimal_temperature => 22.28 ~ preserve(u"°C", parameter)
    T_ceil: ceiling_temperature => 34.23 ~ preserve(u"°C", parameter)

    #TODO support species/cultivar specific temperature parameters (i.e. Tb => 8, Tx => 43.3)
    GD(context, T, Tb=4.0u"°C", Tx=40.0u"°C"): growing_degree ~ ::GrowingDegree
    BF(context, T, To=T_opt', Tx=T_ceil'): beta_function ~ ::BetaFunction
    Q10(context, T, To=T_opt'): q10_function ~ ::Q10Function

    # garlic

    #FIXME clear definition of bulb maturing
    #bulb_maturing(scape_removed, bulbil_appeared) => (scape_removed || bulbil_appeared) ~ flag

    # common

    # # GDDsum
    # gdd_after_emergence(emerged, r=gdd_recorder.rate) => begin
    #     #HACK tracker is reset when emergence is over
    #     emerged ? r : 0
    # end ~ track
    #
    # current_stage(emerged, dead) => begin
    #     if emerged
    #         "Emerged"
    #     elseif dead
    #         "Inactive"
    #     else
    #         "none"
    #     end
    # end ~ track::String

    development_phase(germinated, floral_initiated, dead, scape_removed) => begin
        if !germinated
            :seed
        elseif !floral_initiated
            :vegetative
        elseif dead
            :dead
        elseif !scape_removed
            :bulb_growth_with_scape
        else
            :bulb_growth_without_scape
        end
    end ~ track::Symbol
end

@system PhenologyController(Controller) begin
    weather(context) ~ ::Weather
    sun(context, weather) ~ ::Sun
    soil(context) ~ ::Soil
    phenology(context, weather, sun, soil): p ~ ::Phenology
    duration: d => 100 ~ preserve(u"d", parameter)
    stop(context.clock.tick, d) => tick >= d ~ flag
end

plot_pheno(v, d=300) = begin
    o = (
        :Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
        :Weather => (:filename => "test/garlic/data/2007.wea"),
        :Phenology => (:planting_date => ZonedDateTime(2007, 11, 1, tz"UTC")),
        :PhenologyController => (:duration => d),
    )
    r = simulate(PhenologyController, stop=:stop, config=o, base=:phenology)
    Cropbox.plot(r, :tick, v)
end
