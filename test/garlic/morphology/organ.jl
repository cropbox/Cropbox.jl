@system Organ begin
    pheno: phenology ~ ::Phenology(override)

    # organ temperature, C
    T(pheno.T): temperature ~ track(u"°C")

    # glucose, MW = 180.18 / 6 = 30.03 g
    C(imported_carbohydrate): carbohydrate => begin
        imported_carbohydrate # * respiration_adjustment
    end ~ accumulate(u"g") # CH2O

    # nitrogen content, mg
    N(imported_nitrogen): nitrogen => begin
        imported_nitrogen
    end ~ accumulate(u"g") # Nitrogen

    # physiological age accounting for temperature effect (in reference to endGrowth and lifeSpan, days)
    #HACK: tracking should happen after plant emergence (due to implementation of original beginFromEmergence)
    physiological_age(pheno.GD.r) ~ accumulate(when=pheno.emerged, u"K")

    # chronological age of an organ, days
    chronological_age => 1 ~ accumulate(u"d")

    # biomass, g
    # @derive
    # def mass(self):
    #     #FIXME isn't it just the amount of carbohydrate?
    #     #self._carbohydrate / Weight.CH2O * Weight.C / Weight.C_to_CH2O_ratio
    #     self._carbohydrate
    #FIXME need unit conversion from CH2O?
    mass(C) ~ track(u"g") # CH2O

    # #TODO remove set_mass() and directly access carbohydrate
    # def set_mass(self, mass):
    #     #self._carbohydrate = mass * Weight.C_to_CH2O_ratio / Weight.C * Weight.CH2O
    #     self._carbohydrate = mass

    # physiological days to reach the end of growth (both cell division and expansion) at optimal temperature, days
    GD: growth_duration => 10 ~ preserve(u"d", parameter)

    # life expectancy of an organ in days at optimal temperature (fastest growing temp), days
    #FIXME not used
    longevity => 50 ~ preserve(u"d", parameter)

    # carbon allocation to roots or leaves for time increment
    #FIXME not used
    potential_carbohydrate_increment => 0 ~ track(u"g/hr") # CH2O

    # carbon allocation to roots or leaves for time increment  gr C for roots, gr carbo dt-1
    #FIXME not used
    actual_carbohydrate_increment => 0 ~ track(u"g/hr") # CH2O

    #TODO to be overridden
    imported_carbohydrate => 0 ~ track(u"g/hr") # CH2O

    #TODO think about unit
    respiration_adjustment(Ka=0.1, Rm=0.02) => begin
        # this needs to be worked on, currently not used at all
        # Ka: growth respiration
        # Rm: maintenance respiration
        1 - (Ka + Rm)
    end ~ track

    #TODO to be overridden
    imported_nitrogen => 0 ~ track(u"g/hr") # Nitrogen
end
