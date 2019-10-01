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

    carbon_reserve(seed_mass_export_rate, C_conc, C_to_CH2O_ratio) => begin
        seed_mass_export_rate * C_conc * C_to_CH2O_ratio
    end ~ accumulate(u"g")

    carbon_pool(assimilation, supply) => begin
        assimilation - supply
    end ~ accumulate(u"g")



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

        #FIXME use simple Beta function for garlic
        beta_thermal_func(T, T_opt, T_ceil)
    end ~ track

    carbon_growth_factor => begin
        # translocation limitation and lag, assume it takes 1 hours to complete, 0.2=5 hrs
        # this is where source/sink (supply/demand) valve can come in to play
        # 0.2 is value for hourly interval, Grant (1989)
        1 / 5u"hr"
    end ~ preserve(u"hr^-1")

    # this is the same as (PhyllochronsSinceTI - lvsAtTI / (totalLeaves - lvsAtTI))
    carbon_scale => begin
        #FIXME support multiple species
        # for maize
        # see Grant (1989), #of phy elapsed since TI/# of phy between TI and silking
        #self.p.pheno.grant_scale
        # not correctly implemented yet for garlic
        1.0
    end ~ preserve

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

    @property
    def demand(self):
        # for maize
        # if self.p.pheno.grain_filling:
        #     # here only grain and root dry matter increases root should be zero but it is small now.
        #     max_kernel_no = 800 # assumed maximum kerner number per ear
        #     # max kernel filling rate = 0.012g Kernel-1 day-1, Grant (1989)
        #     dt = self.p.initials.timestep / (24 * 60)
        #     max_kernel_fill_rate = 0.012 * dt
        #     #dt added c_content
        #     return max_kernel_no * max_kernel_fill_rate * self._temperature_effect * self._content
        # else:
        #     return 0
        # for garlic
        return 0


class Carbon(Trait):
    def setup(self):
        self.reserve = 0
        self.pool = 0
        self.root_pool = 0
        self.supply = 0 # daily mobilization of carbon
        #self.demand = 0 # property

        self.allocate_reserve_from_seed()

        # assume it takes 20 days to exhaust seed C reserve
        #self.translocate_to_pool(self.reserve * (1/20) * (1/24) * (self.p.initials.timestep / 60))
        self.translocate_to_pool()
        #FIXME the original code did not reset reserve here
        #self.reserve = self.pool

    def translocate_to_pool(self, amount=None):
        if amount is None:
            amount = self.reserve
        else:
            amount = min(self.reserve, amount)
        self.reserve -= amount
        self.pool += amount
        if self.pool < 0:
            import pdb; pdb.set_trace()

    def assimilate_to_pool(self, amount=None):
        # import datetime
        # if self.p.weather.time >= datetime.datetime(2007, 6, 3).astimezone(self.p.weather.time.tz):
        #     import pdb; pdb.set_trace()

        #HACK should be the amount of carbohydrate (less), not CO2
        #amount = self.p.photosynthesis.assimilation * (Weight.CH2O / Weight.CO2)
        amount = self.p.photosynthesis.gross
        #print("assim = {}".format(amount))
        self.pool += amount
        if self.pool < 0:
            import pdb; pdb.set_trace()

    #TODO merge consume_pool / reserve with a solid logic
    def consume_pool(self, amount):
        #FIXME no boundary check
        self.pool -= amount
        if self.pool < 0:
            import pdb; pdb.set_trace()

    def consume_reserve(self, amount):
        self.reserve -= amount
        if self.reserve < 0:
            import pdb; pdb.set_trace()

    def reset_pool(self):
        # reset shorterm C_pool to zero at midnight, needs to be more mechanistic
        #FIXME need max(0, self.pool)?
        if self.pool < 0 and not np.isclose(self.pool, 0):
            import pdb; pdb.set_trace()
        self.reserve += self.pool
        self.pool = 0

    def reset_root_pool(self):
        self.root_pool = 0

    def update_root_pool_with_residual(self):
        #TODO need output from 2DSOIL
        pcrl = self.p.soil.min_root_carbon_supply_rate
        pcrs = self.p.soil.actual_root_carbon_supply_rate
        self.root_pool += pcrl - pcrs

    @property
    def _content(self):
        #HACK should depend on growth stage, but fix it for now
        return self.p.ratio.carbon_to_mass




    #TODO rethink the entire logic!!!
    def make_supply(self):
        # C_demand does not enter into equations until grain fill
        translocation_rate = self._temperature_effect * self._growth_factor
        maintenance_respiration = self.maintenance_respiration

        #HACK handle residual root carbon from 2DSOIL here, not in partition()
        #FIXME only for MAIZSIM
        #self.update_root_pool_with_residual()

        if self.pool > self.demand:
            # CADD from Grant
            self.supply = self.pool * translocation_rate
            # C_Pool is what is left over from the carbon available for growth
            self.consume_pool(self.supply)
        elif np.isclose(self.pool, 0): # self.pool == 0:
            if self.reserve > 0:
                # all the reserve is not available
                #FIXME why translocation from the reserve has the same rate?
                self.supply = self.reserve * translocation_rate
                # reduce reserve pool for used carbon
                self.consume_reserve(self.supply)
            else:
                #TODO what would happen if no reserve available?
                import pdb; pdb.set_trace()
                pass
        elif self.reserve > self.demand > 0:
            # conversion and translocation from long term reserve should be less efficient, apply nother glucose conversion factor
            # translocation from the soluble sugar reserve
            #TODO: prevent negative pool beforehand?
            if self.pool < 0:
                # C_pool negative here, add instead of subtract
                self.reset_pool()
            # deplete C_pool first* tmprEffect
            #FIXME why supply size depends on the total demand unlike other cases?
            self.supply = self.demand * translocation_rate
            self.consume_reserve(self.supply) # reserve C is used to increase grain mass
            #FIXME isn't it duplicate of negative pool handling right above?
            # send remaining C (not enough to meet the demand) in shorterm pool to reserve
            # empty the C_pool
            self.reset_pool()

        #FIXME handling of maintenance respiration starts here, but not sure it should be
        elif self.pool > maintenance_respiration:
            self.supply = maintenance_respiration
            self.consume_pool(self.supply)
        elif self.reserve > maintenance_respiration:
            self.supply = maintenance_respiration
            self.consume_reserve(self.supply)
            self.reset_pool()
            # In this way, the c_reserve is used to satisfy the maintainance respiration demand. Then C_pool is
            # used to replenish C_reserve and then C_pool is set to 0. In other words, C_pool is depleted first
            # and then C_reserve is used to supplement whatever demand that's left
        else:
            self.reset_pool()
            self.supply = min(self.reserve, maintenance_respiration)
            #FIXME no need to consume supply from reserve?

        #HACK handle remaining reserve here
        # everything is carbohydrate now
        #FIXME shoot reserve is only for maize?
        #self.reserve += self.shoot_reserve

    @property
    def partition(self):
        # for MAIZSIM
        fraction = min(0.925, 0.50 + 0.50 * self._scale) # eq 3 in Grant
        #conv_factor = 1 / 1.43 # equivalent Yg, Goudriaan and van Laar (1994)
        #Yg = 0.75 # synthesis efficiency, ranges between 0.7 to 0.76 for corn, see Loomis and Amthor (1999), Grant (1989), McCree (1988)
        # Yg = 0.74

        # for garlic
        fraction = min(0.925, 0.67 + 0.33 * self._scale) # eq 3 in Grant
        Yg = self.p.initials.Yg

        c = max(self.supply - self.maintenance_respiration, 0)
        # for maize
        # if self.p.pheno.grain_filling:
        #FIXME split carbon modules for maize and garlic
        if False:
            shoot = Yg * c # gCH2O partitioned to shoot
            root = 0 # no more partitioning to root during grain fill
        #HACK unused code
        # elif self.p.pheno.vegetative_growing:
            # shootPart was reduced to 0.37; rootPart was 0.43 in sourcesafe file yy
            # SK, commenting it out. Yg needs to be multiplied here because it represents growth respiration.
            # shoot = 0.67 * c # these are the amount of carbons allocated with no drought stress
            # root = 0.33 * c # Yang, 6/22/2003
        else:
            shoot = fraction * Yg * c # gCH2O partitioned to shoot
            root = (1 - fraction) * Yg * c # gCH2O partitioned to roots

        #HACK replaced by update_root_pool_with_residual()
        # #TODO need output from 2DSOIL
        # diff = self.p.soil.pcrs - self.p.soil.pcrl:
        # # if in time step t-1, the value of pcrs is higher than that of pcrl
        # if diff > 0:
        #     # give a half of carbon from shoot needed to meet root demand? SK
        #     # then take the difference between the two out of the carbon allocation to shoot at time step t
        #     shoot -= min(diff, shoot)
        #     # and put that amount of carbon into carbon allocation to root at time step t.
        #     root += diff
        # else:
        #     #HACK side effect here can't make this method @property
        #     self.pool -= diff
        #     # subtract out carbon sent to the root pool
        #     root += diff

        return {
            'shoot': shoot,
            'root': root,
        }

    @property
    def shoot(self):
        return self.partition['shoot']

    @property
    def root(self):
        return self.partition['root']

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
