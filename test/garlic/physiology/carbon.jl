@system RespirationTracker(Q10Function) begin
    w: weather ~ ::Weather(override)
    T(w.T_air): temperature ~ track(u"°C") # should be soil temperature
    To: optimal_temperature => 20 ~ preserve(u"°C", parameter)
    Q10 => begin
        # typical Q10 value for respiration, Loomis and Amthor (1999) Crop Sci 39:1584-1596
        2
    end ~ preserve(parameter)
end

@system Carbon begin
    weather ~ hold
    pheno: phenology ~ hold

    C_to_CH2O_ratio ~ hold
    seed_mass_export_rate ~ hold
    assimilation ~ hold
    total_mass ~ hold
    green_leaf_ratio ~ hold

    dp(pheno.development_phase): development_phase ~ track::sym

    C_conc: carbon_concentration => begin
        # maize: 40% C, See Kim et al. (2007) EEB
        0.45
    end ~ preserve(u"percent")

    carbon_reserve_from_seed(seed_mass_export_rate, C_conc, C_to_CH2O_ratio) => begin
        seed_mass_export_rate * C_conc * C_to_CH2O_ratio
    end ~ track(u"g/d")

    #TODO: take account NSC from bulb
    carbon_reserve(carbon_reserve_from_seed, carbon_translocation) => begin
        carbon_reserve_from_seed - carbon_translocation
    end ~ accumulate(u"g")

    carbon_translocation(carbon_pool, carbon_reserve, carbon_translocation_rate) => begin
        c = sign(carbon_pool) < 0 ? carbon_reserve : zero(carbon_reserve)
        c * carbon_translocation_rate
    end ~ track(u"g/d")

    carbon_pool(assimilation, carbon_translocation, carbon_supply) => begin
        assimilation + carbon_translocation - carbon_supply
    end ~ accumulate(u"g")

    carbon_supply(carbon_pool, carbon_supply_rate) => begin
        carbon_pool * carbon_supply_rate
    end ~ track(u"g/d")

    # to be used by allocate_carbon()
    carbon_temperature_effect(T=nounit(weather.T_air, u"°C"), β=pheno.BF.ΔT) => begin
        #FIXME properly handle T_air
        # this needs to be f of temperature, source/sink relations, nitrogen, and probably water
        # a valve function is necessary because assimilates from CPool cannot be dumped instantaneously to parts
        # this may be used for implementing feedback inhibition due to high sugar content in the leaves
        # The following is based on Grant (1989) AJ 81:563-571

        # Normalized (0 to 1) temperature response fn parameters, Pasian and Lieth (1990)
        # Lieth and Pasian Scientifica Hortuculturae 46:109-128 1991
        # parameters were fit using rose data -
        b1 = 2.325152587
        b2 = 0.185418876 # I'm using this because it can have broad optimal region unlike beta fn or Arrhenius eqn
        b3 = 0.203535650
        Td = 48.6 #High temperature compensation point

        g1 = 1 + exp(b1 - b2 * T)
        g2 = 1 - exp(-b3 * max(0, Td - T))
        #return g2 / g1

        β
    end ~ track

    carbon_growth_factor => begin
        # translocation limitation and lag, assume it takes 1 hours to complete, 0.2=5 hrs
        # this is where source/sink (supply/demand) valve can come in to play
        # 0.2 is value for hourly interval, Grant (1989)
        1 / 5u"hr"
    end ~ preserve(u"hr^-1")

    carbon_translocation_rate(carbon_temperature_effect, carbon_growth_factor) => begin
        # C_demand does not enter into equations until grain fill
        carbon_temperature_effect * carbon_growth_factor
    end ~ track(u"hr^-1")

    carbon_supply_rate(carbon_temperature_effect, carbon_growth_factor) => begin
        carbon_temperature_effect * carbon_growth_factor
    end ~ track(u"hr^-1")

    Rm: maintenance_respiration_coefficient => begin
        # gCH2O g-1DM day-1 at 20C for young plants, Goudriaan and van Laar (1994) Wageningen textbook p 54, 60-61
        #0.015
        #0.018 # for maize
        0.012
    end ~ preserve(u"g/g/d", parameter)

    agefn(green_leaf_ratio): carbon_age_effect => begin
        # as more leaves senesce maint cost should go down, added 1 to both denom and numer to avoid division by zero.
        #agefn = (self.p.area.green_leaf + 1) / (self.p.area.leaf + 1)
        # no maint cost for dead materials but needs to be more mechanistic, SK
        #agefn = 1.0
        # from garlic model
        #agefn = (self.p.area.green_leaf + 0.1) / (self.p.area.leaf + 0.1)
        green_leaf_ratio
    end ~ track

    # based on McCree's paradigm, See McCree(1988), Amthor (2000), Goudriaan and van Laar (1994)
    # units very important here, be explicit whether dealing with gC, gCH2O, or gCO2
    maintenance_respiration_tracker(context, weather) ~ ::RespirationTracker
    maintenance_respiration(total_mass, Rm, agefn, q=maintenance_respiration_tracker.ΔT) => begin
        total_mass * q * Rm # gCH2O dt-1, agefn effect removed. 11/17/14. SK.
    end ~ track(u"g/d")

    carbon_available(carbon_supply, maintenance_respiration) => begin
        carbon_supply - maintenance_respiration
    end ~ track(u"g/d", min=0)

    # this is the same as (PhyllochronsSinceTI - lvsAtTI / (totalLeaves - lvsAtTI))
    carbon_scale => begin
        #FIXME support multiple species
        # for maize
        # see Grant (1989), #of phy elapsed since TI/# of phy between TI and silking
        #self.p.pheno.grant_scale
        # not correctly implemented yet for garlic
        1.0
    end ~ preserve

    carbon_fraction(s=carbon_scale) => begin
        # eq 3 in Grant
        #0.50 + 0.50s # for MAIZSIM
        0.67 + 0.33s # for garlic
    end ~ track(max=0.925)

    Yg: synthesis_efficiency => begin
        #1 / 1.43 # equivalent Yg, Goudriaan and van Laar (1994)
        #0.75 # synthesis efficiency, ranges between 0.7 to 0.76 for corn, see Loomis and Amthor (1999), Grant (1989), McCree (1988)
        #0.74
        0.8
    end ~ preserve(parameter)

    shoot_carbon(c=carbon_available, carbon_fraction, Yg) => begin
        # for maize
        # if self.p.pheno.grain_filling:
        #     shoot = Yg * c # gCH2O partitioned to shoot
        # elif self.p.pheno.vegetative_growing:
        # # shootPart was reduced to 0.37; rootPart was 0.43 in sourcesafe file yy
        # # SK, commenting it out. Yg needs to be multiplied here because it represents growth respiration.
        #     shoot = 0.67 * c # these are the amount of carbons allocated with no drought stress
        carbon_fraction * Yg * c # gCH2O partitioned to shoot
    end ~ track(u"g/d")

    root_carbon(c=carbon_available, carbon_fraction, Yg) => begin
        # for maize
        # if self.p.pheno.grain_filling:
        #     root = 0 # no more partitioning to root during grain fill
        # elif self.p.pheno.vegetative_growing:
        # # shootPart was reduced to 0.37; rootPart was 0.43 in sourcesafe file yy
        # # SK, commenting it out. Yg needs to be multiplied here because it represents growth respiration.
        #     root = 0.33 * c # Yang, 6/22/2003
        (1 - carbon_fraction) * Yg * c # gCH2O partitioned to roots
    end ~ track(u"g/d")

    pt: partitioning_table => [
        # root shoot leaf sheath scape bulb
          0.00  0.00 0.00   0.00  0.00 0.00 ; # seed
          0.10  0.00 0.45   0.45  0.00 0.00 ; # vegetative
          0.10  0.00 0.15   0.25  0.10 0.40 ; # bulb growth with scape
          0.10  0.00 0.15   0.30  0.00 0.45 ; # bulb growth without scape
          0.00  0.00 0.00   0.00  0.00 0.00 ; # dead
    ] ~ tabulate(
        rows=(:seed, :vegetative, :bulb_growth_with_scape, :bulb_growth_without_scape, :dead),
        columns=(:root, :shoot, :leaf, :sheath, :scape, :bulb),
        parameter
    )

    leaf_carbon(shoot_carbon, pt, dp) => begin
        shoot_carbon * pt[dp].leaf
    end ~ track(u"g/d")

    sheath_carbon(shoot_carbon, pt, dp) => begin
        shoot_carbon * pt[dp].sheath
    end ~ track(u"g/d")

    scape_carbon(shoot_carbon, pt, dp) => begin
        shoot_carbon * pt[dp].scape
    end ~ track(u"g/d")

    bulb_carbon(shoot_carbon, pt, dp) => begin
        shoot_carbon * pt[dp].bulb
    end ~ track(u"g/d")
end
