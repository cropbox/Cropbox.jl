@system Carbon begin
    weather ~ hold
    phenology: pheno ~ hold

    #planting_density ~ hold

    C_to_CH2O_ratio ~ hold

    seed_mass_export_rate ~ hold
    #shoot_mass ~ hold

    total_mass ~ hold
    green_leaf_ratio ~ hold

    carbon_concentration: C_conc => begin
        # maize: 40% C, See Kim et al. (2007) EEB
        0.45
    end ~ preserve(u"percent")

    carbon_reserve_from_seed(seed_mass_export_rate, C_conc, C_to_CH2O_ratio) => begin
        seed_mass_export_rate * C_conc * C_to_CH2O_ratio
    end ~ track(u"g/d")

    #TODO: take account NSC from bulb
    carbon_reserve(carbon_reserve_from_seed, carbon_reserve_use) => begin
        carbon_reserve_from_seed - carbon_reserve_use
    end ~ accumulate(u"g")

    carbon_translocation(carbon_pool, carbon_reserve, carbon_translocation_rate) => begin
        carbon_pool < 0 ? carbon_reserve * carbon_translocation_rate : 0
    end ~ track(u"g/d")

    carbon_pool(assimilation, carbon_translocation, carbon_pool_use) => begin
        assimilation + carbon_translocation - carbon_supply
    end ~ accumulate(u"g")

    carbon_supply(carbon_pool, carbon_supply_rate) => begin
        carbon_pool * carbon_supply_rate
    end ~ track(u"g/d")

    # to be used by allocate_carbon()
    carbon_temperature_effect(T_air=weather.T_air, T_opt=pheno.T_opt, T_ceil=pheno.T_ceil) => begin
        #FIXME properly handle T_air
        T = ustrip(u"°C", T_air)
        # this needs to be f of temperature, source/sink relations, nitrogen, and probably water
        # a valve function is necessary because assimilates from CPool cannot be dumped instantanesly to parts
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

        beta_thermal_func(T, T_opt, T_ceil)
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

    maintenance_respiration_coefficient: Rm => begin
        # gCH2O g-1DM day-1 at 20C for young plants, Goudriaan and van Laar (1994) Wageningen textbook p 54, 60-61
        #0.015
        #0.018 # for maize
        0.012
    end ~ preserve(u"g/g/d")

    carbon_age_effect(green_leaf_ratio): agefn => begin
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
    maintenance_respiration(total_mass, T_air=weather.T_air, Rm, agefn) => begin
        # typical Q10 value for respiration, Loomis and Amthor (1999) Crop Sci 39:1584-1596
        Q10 = 2
        T = T_air # should be soil temperature
        T_opt = 20u"°C"
        dt = u"d"
        q = q10_thermal_func(T, T_opt; Q10=Q10)
        total_mass * q * Rm / dt # gCH2O dt-1, agefn effect removed. 11/17/14. SK.
    end ~ track(u"g/d")

    carbon_available(carbon_supply, maintenance_respiration) => begin
        c = carbon_supply - maintenance_respiration
        max(c, zero(c))
    end ~ track(u"g/d")

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
        #min(0.925, 0.50 + 0.50s) # for MAIZSIM
        min(0.925, 0.67 + 0.33s) # for garlic
    end ~ track

    synthesis_efficiency: Yg => begin
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

    partitioning_table => begin
        # seed, vegetative, bulb growth w/scape, wo/scape, dead
        DataFrame(
            root   = [0.00, 0.10, 0.10, 0.10, 0.00],
            shoot  = [0.00, 0.00, 0.00, 0.00, 0.00],
            leaf   = [0.00, 0.45, 0.15, 0.15, 0.00],
            sheath = [0.00, 0.45, 0.25, 0.30, 0.00],
            bulb   = [0.00, 0.00, 0.40, 0.45, 0.00],
        )
    end ~ preserve::DataFrame

    # for maize

    # @property
    # def partition_shoot(self):
    #     shoot = self.shoot
    #     #FIXME: vegetative growth
    #     #if self.p.pheno.vegetative_growing:
    #     if not self.p.pheno.tassel_initiated:
    #         return {
    #             'leaf': shoot * 0.725,
    #             'sheath': shoot * 0.275,
    #             'stalk': 0,
    #             'reserve': 0,
    #             'husk': 0,
    #             'cob': 0,
    #             'grain': 0,
    #         }
    #     #FIXME: there is a period after silking and before grain filling that not handled by this function
    #     #elif self.p.pheno.silking:
    #     elif not self.p.pheno.grain_filling:
    #         s = self._scale
    #         def ratio(a, b, t):
    #             r = a if s <= t else b
    #             return shoot * max(r, 0)
    #         leaf = ratio(0.725 - 0.775*s, 0, s)
    #         sheath = ratio(0.275 - 0.225*s, 0, s)
    #         #HACK: extended growth period for testing different allocation pattern with Maryland05 dataset
    #         #leaf = shoot * max(0.725 - 0.775*s*0.7, 0)
    #         #sheath = shoot * max(0.275 - 0.225*s*0.7, 0)
    #         #TODO check if stalk ratio is conditioned this way, otherwise reserve_ratio should be computed here
    #         #stalk = ratio(1.1*s, 2.33 - 0.6*np.exp(s), 0.85)
    #         stalk = ratio(1.1*s, 0, 0.85)
    #         reserve = ratio(0, 2.33 - 0.6*np.exp(s), 0.85)
    #         husk = ratio(np.exp(-7.75 + 6.6*s), 1 - 0.675*s, 1.0)
    #         cob = ratio(np.exp(-8.4 + 7.0*s), 0.625, 1.125)
    #         # give reserve part what is left over, right now it is too high
    #         if reserve > 0:
    #             reserve = max(shoot - (leaf + sheath + stalk + husk + cob), 0)
    #         # allocate shootPart into components
    #         return {
    #             'leaf': leaf,
    #             'sheath': sheath,
    #             'stalk': stalk,
    #             'reserve': reserve,
    #             'husk': husk,
    #             'cob': cob,
    #             'grain': 0,
    #         }
    #     #TODO: check if it should go further than grain filling until dead
    #     elif self.p.pheno.grain_filling:
    #         return {
    #             'leaf': 0,
    #             'sheath': 0,
    #             'stalk': 0,
    #             'reserve': 0,
    #             'husk': 0,
    #             'cob': 0,
    #             'grain': shoot,
    #         }

    # @property
    # def leaf(self):
    #     return self.partition_shoot['leaf']
    #
    # @property
    # def sheath(self):
    #     return self.partition_shoot['sheath']
    #
    # @property
    # def stalk(self):
    #     return self.partition_shoot['stalk']
    #
    # @property
    # #FIXME shouldn't be confused with long-term reserve pool
    # def shoot_reserve(self):
    #     return self.partition_shoot['reserve']
    #
    # @property
    # def husk(self):
    #     return self.partition_shoot['husk']
    #
    # @property
    # def cob(self):
    #     return self.partition_shoot['cob']
    #
    # @property
    # def grain(self):
    #     return self.partition_shoot['grain']
    #
    # @property
    # def stem(self):
    #     #TODO sheath and stalk haven't been separated in this model
    #     # shoot_reserve needs to be added later
    #     return self.sheath + self.stalk
    #
    # @property
    # def ear(self):
    #     return self.grain + self.cob + self.husk

    # for garlic
    #TODO implement more programmatic way to access partition table

    @property
    def leaf(self):
        return self.shoot * self.p.initials[f'partition_{self.p.pheno.development_phase}_leaf']

    @property
    def sheath(self):
        return self.shoot * self.p.initials[f'partition_{self.p.pheno.development_phase}_sheath']

    @property
    def scape(self):
        return self.shoot * self.p.initials[f'partition_{self.p.pheno.development_phase}_scape']

    @property
    def bulb(self):
        return self.shoot * self.p.initials[f'partition_{self.p.pheno.development_phase}_bulb']

    def prepare_mobilization(self):
        pass
