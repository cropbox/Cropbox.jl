include("stage.jl")

include("bulbing.jl")
include("death.jl")
include("emergence.jl")
include("floralinitiation.jl")
include("germination.jl")
include("leafappearance.jl")
include("leafinitiation.jl")
include("scape.jl")

#TODO make a common class to be shared by Garlic and MAIZSIM
@system Phenology begin
    weather => Weather(; context=context) ~ ::Weather
    soil => Soil(; context=context) ~ ::Soil

    optimal_temperature: T_opt => 22.28 ~ preserve(u"°C", parameter)
    ceiling_temperature: T_ceil => 34.23 ~ preserve(u"°C", parameter)

    #FIXME: remove them since they're in defined at individual system level

    # storage_days => 0 ~ preserve(parameter)
    # initial_leaves_at_harvest: ILN => 4 ~ preserve(parameter)

    # maximum_leaf_initiation_rate: R_max_LIR => 0 ~ preserve(parameter)
    # maximum_leaf_tip_appearance_rate: R_max_LTAR => 0 ~ preserve(parameter)

    # critical_photoperiod => 12 ~ preserve(parameter)

    #emergence_date => ZonedDateTime() ~ preserve(parameter)
    #scape_removal_date => ZonedDateTime() ~ preserve(parameter)

    # def setup(self):
    #     # mean growing season temperature since germination, SK 1-19-12
    #     self.gst_recorder = gstr = GstRecorder(self)
    #     self.gdd_recorder = gddr = GddRecorder(self)
    #     self.gti_recorder = gtir = GtiRecorder(self)

    #     self.germination = g = Germination(self)
    #     self.emergence = e = Emergence(self, R_max=R_max_LTAR, T_opt=T_opt, T_ceil=T_ceil, emergence_date=emergence_date)
    #     self.leaf_initiation = li = LeafInitiationWithStorage(self, initial_leaves_at_harvest=initial_leaf_number_at_harvest, R_max=R_max_LIR, T_opt=T_opt, T_ceil=T_ceil, storage_days=storage_days)
    #     self.leaf_appearance = la = LeafAppearance(self, R_max=R_max_LTAR, T_opt=T_opt, T_ceil=T_ceil)
    #     self.floral_initiation = fi = FloralInitiation(self, critical_photoperiod=critical_photoperiod)
    #     self.bulbing = bi = Bulbing(self)
    #     self.scape = s = Scape(self, R_max=R_max_LTAR, T_opt=T_opt, T_ceil=T_ceil)
    #     self.scape_appearance = sa = ScapeAppearance(self, s)
    #     self.scape_removal = sr = ScapeRemoval(self, s, scape_removal_date=scape_removal_date)
    #     self.flowering = f = Flowering(self, s)
    #     self.bulbiling = b = Bulbiling(self, s)
    #     self.death = d = Death(self)

    #     self.stages = [
    #         gstr, gddr, gtir,
    #         g, e, li, la, fi, bi, s, sa, sr, f, b, d,
    #     ]

    # def update(self, t):
    #     #queue = self._queue()
    #     [s.update(t) for s in self.stages if s.ready]

    #     #FIXME remove finish() for simplicity
    #     [s.finish() for s in self.stages if s.over]

    #     self.stages = [s for s in self.stages if not s.over]

    # #TODO some methods for event records? or save them in Stage objects?
    # #def record(self, ...):
    # #    pass

    germination => Germination(; context=context, phenology=self) ~ ::System
    emergence => Emergence(; context=context, phenology=self) ~ ::System
    leaf_initiation => LeafInitiationWithStorage(; context=context, phenology=self) ~ ::System
    leaf_appearance => LeafAppearance(; context=context, phenology=self) ~ ::System
    floral_initiation => FloralInitiation(; context=context, phenology=self) ~ ::System
    bulbing => Bulbing(; context=context, phenology=self) ~ ::System
    scape => Scape(; context=context, phenology=self) ~ ::System(expose)
    scape_appearance => ScapeAppearance(; context=context, phenology=self, scape=scape) ~ ::System
    scape_removal => ScapeRemoval(; context=context, phenology=self, scape=scape) ~ ::System
    flowering => Flowering(; context=context, phenology=self, scape=scape) ~ ::System
    bulbiling => Bulbiling(; context=context, phenology=self, scape=scape) ~ ::System
    death => Death(; context=context, phenology=self) ~ ::System

    ############
    # Accessor #
    ############

    leaves_generic => 10 ~ preserve(parameter)
    leaves_potential(leaves_generic, leaves_total) => max(leaves_generic, leaves_total) ~ track
    leaves_total(leaves_initiated) ~ track
    leaves_initiated("leaf_initiation.leaves") ~ track
    leaves_appeared("leaf_appearance.leaves") ~ track

    temperature(leaves_appeared, T_air="weather.T_air"): T => begin
        if leaves_appeared < 9
            #FIXME soil module is not implemented yet
            #T = T_soil
            #HACK garlic model does not use soil temperature
            T = T_air
        else
            T = T_air
        end
        #FIXME T_cur doesn't go below zero, but is it fair assumption?
        max(T, 0u"°C")
    end ~ track(u"°C")
    #growing_temperature(r="gst_recorder.rate") => r ~ track

    # common

    germinating("germination.ing") ~ flag
    germinated("germination.over") ~ flag
    emerging("emergence.ing") ~ flag
    emerged("emergence.over") ~ flag

    # garlic

    floral_initiated("floral_initiation.over") ~ flag
    scaping("scape.ing") ~ flag
    scape_appeared("scape_appearance.over") ~ flag
    scape_removed("scape_removal.over") ~ flag
    flowered("flowering.over") ~ flag
    #FIXME clear definition of bulb maturing
    bulb_maturing(scape_removed, f="bulbiling.over") => (scape_removed || f) ~ flag

    # common

    dead("death.over") ~ flag

    # # GDDsum
    # gdd_after_emergence(emerged, r="gdd_recorder.rate") => begin
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

plot_pheno(v) = begin
	o = configure(
		:Clock => (:unit => u"hr"),
		:Calendar => (:init => ZonedDateTime(2007, 9, 1, tz"UTC")),
		:Weather => (:filename => "test/garlic/data/2007.wea"),
	)
	s = instance(Phenology; config=o)
	c = s.context
	T = typeof(value(c.clock.tick))[]
	V = typeof(value(s[v]))[]
	while value(c.clock.tick) <= 30u"d"
		#println("t = $(c.clock.tick): v = $(s[v])")
		push!(T, value(c.clock.tick))
		push!(V, value(s[v]))
		advance!(s)
	end
	plot(T, V, xlab="tick", ylab=String(v), xlim=ustrip.((T[1], T[end])), ylim=ustrip.((minimum(V), maximum(V))))
end
