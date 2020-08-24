#TODO move into Leaf class?
@system Nitrogen begin
    pheno: phenology ~ hold
    PD: planting_density ~ hold

    initial_seed_mass ~ hold
    shoot_mass ~ hold
    green_leaf_area ~ hold

    # SK: get N fraction allocated to leaves, this code is just moved from the end of the procedure, this may be taken out to become a separate fn

    # def setup(self):
    #     # assume nitrogen concentration at the beginning is 3.4% of the total weight of the seed
    #     # need to check with Yang. This doesn't look correct
    #     self.set_pool(self.initial_pool)
    #
    #     #TODO set up interface
    #     self.ratio = 0
    #     self.hourly_soil_uptake = 0
    #     self.hourly_demand = 0
    #     self.cumulative_demand = 0
    #     self.cumulative_soil_uptake = 0

    nitrogen_pool_from_shoot(shoot_mass, PD, frac=0.063) => begin
        if shoot_mass * PD <= 100u"g/m^2"
            # when shoot biomass is lower than 100 g/m2, the maximum [N] allowed is 6.3%
            # shoot biomass and Nitrogen are in g
            # need to adjust demand or else there will be mass balance problems
            #FIXME self.initial_pool or just pool?
            #pool = min(0.063 * shoot_mass, self.initial_pool)
            #pool = min(0.063 * shoot_mass, pool)
            frac * shoot_mass
        else
            #FIXME what about other case? should be no cyclic dependency
            #return pool?
            @error "pool_from_shoot"
        end
    end ~ track(u"g") # Nitrogen

    initial_nitrogen_pool(initial_seed_mass, frac=0.034) => begin
        # assume nitrogen concentration at the beginning is 3.4% of the total weight of the seed
        frac * initial_seed_mass # 0.275
    end ~ track(u"g") # Nitrogen

    #FIXME: how to use `initial_pool` when track has no init?
    nitrogen_pool(nitrogen_pool_from_shoot, nitrogen_uptake_from_soil) => begin
        nitrogen_pool_from_shoot + nitrogen_uptake_from_soil
    end ~ track(u"g") # Nitrogen

    #TODO for 2DSOIL interface
    nitrogen_uptake_from_soil => 0 ~ track(u"g") # Nitrogen

    #TODO currently not implemented in the original code
    # def nitrogen_remobilize(self):
    #     pass
        #droppedLfArea = (1-greenLeafArea/potentialLeafArea)*potentialLeafArea; //calculated dropped leaf area YY
        #SK 8/20/10: Changed it to get all non-green leaf area
        #currentDroppedLfArea = droppedLfArea - previousDroppedlfArea; //leaf dropped at this time step
        #this->set_N((this->get_N()-(leaf_N/leafArea)*currentDroppedLfArea)); //calculated the total amount of nitrogen after the dropped leaves take some nitrogen out
        #no nitrogen remobilization from old leaf to young leaf is considered for now YY

    #TODO rename to `leaf_to_plant_ratio`? or just keep it?
    leaf_nitrogen_fraction(tt=pheno.gdd_after_emergence) => begin
        # Calculate faction of nitrogen in leaves (leaf NFraction) as a function of thermal time from emergence
        # Equation from Lindquist et al. 2007 YY
        #SK 08/20/10: TotalNitrogen doesn't seem to be updated at all anywhere else since initialized from the seed content
        #SK: I see this is set in crop.cpp ln 253 from NUptake from 2dsoil
        # but this appears to be the amount gained from the soil for the time step; so how does it represent totalNitrogen of a plant?
        # tt: record thermal time from emergency YY
        # Calculate faction of nitrogen in leaves (leaf NFraction) as a function of thermal time from emergence
        # Equation from Lindquist et al. 2007 YY
        0.79688 - 0.00023747tt - 0.000000086145tt^2
        # fraction of leaf n in total shoot n can't be smaller than zero. YY
    end ~ track(min=0)

    #TODO rename to `leaves`?
    leaf_nitrogen(leaf_nitrogen_fraction, nitrogen_pool) => begin
        # calculate total nitrogen amount in the leaves YY units are grams N in all the leaves
        leaf_nitrogen_fraction * nitrogen_pool
    end ~ track(u"g") # Nitrogen

    #TODO rename to `unit_leaf`?
    # Calculate leaf nitrogen content of per unit area
    leaf_nitrogen_content(leaf_nitrogen, green_leaf_area) => begin
        # defining leaf nitrogen content this way, we did not consider the difference in leaf nitrogen content
        # of sunlit and shaded leaf yet YY
        #SK 8/22/10: set avg greenleaf N content before update in g/m2
        iszero(green_leaf_area) ? 0. : (leaf_nitrogen / green_leaf_area)
    end ~ track(u"g/cm^2") # Nitrogen
end
