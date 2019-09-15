include("stage.jl")
include("germination.jl")
include("emergence.jl")
include("floralinitiation.jl")
include("leafinitiation.jl")
include("leafappearance.jl")
include("bulbappearance.jl")
include("scape.jl")
include("death.jl")

#TODO make a common class to be shared by Garlic and MAIZSIM
@system Phenology(
	Germination,
	Emergence,
	FloralInitiation,
	LeafInitiationWithStorage,
	LeafAppearance,
	BulbAppearance,
	Scape,
	ScapeAppearance,
	ScapeRemoval,
	FlowerAppearance,
	BulbilAppearance,
	Death
) begin
    calendar ~ ::Calendar(override)
    weather ~ ::Weather(override)
	sun ~ ::Sun(override)
    soil ~ ::Soil(override)

	planting_date => nothing ~ preserve(parameter)

    leaves_generic => 10 ~ preserve(parameter)
    leaves_potential(leaves_generic, leaves_total) => max(leaves_generic, leaves_total) ~ track::Int
    leaves_total(leaves_initiated) ~ track::Int

    temperature(leaves_appeared, T_air=weather.T_air): T => begin
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
	optimal_temperature: T_opt => 22.28 ~ preserve(u"°C", parameter)
	ceiling_temperature: T_ceil => 34.23 ~ preserve(u"°C", parameter)

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
    #
    # development_phase(germinated, floral_initiated, dead, scape_removed) => begin
    #     if !germinated
    #         "seed"
    #     elseif !floral_initiated
    #         "vegetative"
    #     elseif dead
    #         "dead"
    #     elseif !scape_removed
    #         "bulb_growth_with_scape"
    #     else
    #         "bulb_growth_without_scape"
    #     end
    # end ~ track::String
end

using Plots
using UnitfulPlots
unicodeplots()

init_pheno() = begin
	o = configure(
		:Clock => (:unit => u"hr"),
		:Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
		:Weather => (:filename => "test/garlic/data/2007.wea"),
		:Phenology => (:planting_date => ZonedDateTime(2007, 11, 1, tz"UTC")),
	)
	#HACK: manually initate them due to Weather/Soil instances
	#s = instance(Phenology; config=o)
	#c = s.context
	c = Cropbox.Context(; config=o)
	l = Cropbox.Calendar(; context=c)
    w = Weather(; context=c, calendar=l)
	s = Sun(; context=c, calendar=l, weather=w)
	r = Soil(; context=c)
	p = Phenology(; context=c, calendar=l, weather=w, sun=s, soil=r)
	append!(c.systems, [l, w, s, r, p])
	c.order.outdated = true
    advance!(c)
	p
end

plot_pheno(v) = begin
	s = init_pheno()
	c = s.context
	T = typeof(Cropbox.value(c.clock.tick))[]
	V = typeof(Cropbox.value(s[v]))[]
	while Cropbox.value(c.clock.tick) <= 300u"d"
		#println("t = $(c.clock.tick): v = $(s[v])")
		push!(T, Cropbox.value(c.clock.tick))
		push!(V, Cropbox.value(s[v]))
		advance!(s)
	end
	plot(T, V, xlab="tick", ylab=String(v), xlim=ustrip.((T[1], T[end])), ylim=ustrip.((minimum(V), maximum(V))))
end
