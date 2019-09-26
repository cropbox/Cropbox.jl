@system Mass begin
    phenology: pheno ~ hold
    nodal_units: nu ~ hold

    initial_leaf_ratio ~ hold
    potential_leaf_area_increase ~ hold

    # seed weight g/seed
    initial_seed_mass => 0.275 ~ preserve(u"g", parameter)

    # 10% available
    seed_mass_export_limit => 10 ~ preserve(u"percent/d")
    seed_mass_export_rate(seed_mass, seed_mass_export_limit, T=pheno.T, T_opt=pheno.T_opt, T_ceil=pheno.T_ceil) => begin
        # reserved in the propagule (e.g., starch in endosperm of seeds)
        #HACK ratio should depend on growth stage, but fix it for now
        T_effect = beta_thermal_func(T, T_opt, T_ceil)
        seed_mass * T_effect * seed_mass_export_limit
    end ~ track(u"g/d")

    #HACK carbon mass of seed is pulled in the reserve
    seed_mass(seed_mass_export_rate) => begin
        -seed_mass_export_rate
    end ~ accumulate(init=initial_seed_mass, u"g")

    #stem(x=nodal_units["*"].stem.mass) => begin # for maize
    sheath_mass(x=nodal_units["*"].sheath.mass) => begin # for garlic
        # dt the addition of C_reserve here only serves to maintain a total for the mass. It could have just as easily been added to total mass.
        # C_reserve is added to stem here to represent soluble TNC, SK
        #sum(typeof(0.0u"g")[Cropbox.value!(nu.stem.mass) for nu in NU]) + self.p.carbon.reserve
        #sum(typeof(0.0u"g")[Cropbox.value!(nu.sheath.mass) for nu in NU]) + self.p.carbon.reserve
        #FIXME carbon not ready yet
        sum(x)
    end ~ track(u"g")

    initial_leaf_mass(initial_seed_mass, initial_leaf_ratio) => begin
        initial_seed_mass * initial_leaf_ratio
    end ~ track(u"g")

    # this is the total mass of active leaves that are not entirely dead (e.g., dropped).
    # It would be slightly greather than the green leaf mass because some senesced leaf area is included until they are complely aged (dead), SK
    active_leaf_mass(nodal_units, x=nodal_units["*"].leaf.mass) => begin
        sum(typeof(0.0u"g")[Cropbox.value(nu.leaf.mass) for nu in nodal_units if !Cropbox.value(nu.leaf.dropped)])
    end ~ track(u"g")
    #TODO: support complex composition (i.e. `!`(leaf.dropped)) in condition syntax?
    #active_leaf_mass(x=nodal_units["*/!leaf.dropped"].leaf.mass) => sum(x) ~ track(u"g")

    dropped_leaf_mass(nodal_units, x=nodal_units["*"].leaf.mass) => begin
        sum(typeof(0.0u"g")[Cropbox.value(nu.leaf.mass) for nu in nodal_units if Cropbox.value(nu.leaf.dropped)])
    end ~ track(u"g")
    #TODO: support more referencing options (i.e. "leaf.dropped") in condition syntax?
    #dropped_leaf(x=nodal_units["*/leaf.dropped"].leaf.mass) => sum(x) ~ track(u"g")

    total_leaf_mass(x=nodal_units["*"].leaf.mass) => begin
        # this should equal to activeLeafMass + droppedLeafMass
        sum(x)
    end ~ track(u"g")

    leaf_mass(total_leaf_mass) ~ track(u"g")

    # for maize

    # ear_mass(ear.mass) ~ track(u"g")

    # for garlic

    bulb_mass => begin
        #FIXME handling None
        #bulb.mass
        0
    end ~ track(u"g")

    scape_mass => begin
        #FIXME handling None
        #scape.mass
        0
    end ~ track(u"g")

    stalk_mass => begin
        #FIXME inconsistency: stem vs. sheath
        #FIXME handling None
        #sheath_mass + scape_mass
        0
    end ~ track(u"g")

    root_mass => begin
        #FIXME handling None
        #root.mass
        0
    end ~ track(u"g")

    shoot_mass => begin
        # for maize
        #seed_mass + stem_mass + leaf_mass + ear_mass
        # for garlic
        #FIXME handling None
        #seed_mass + stalk_mass + leaf_mass + bulb_mass
        0
    end ~ track(u"g")

    total_mass => begin
        #HACK include mobilized carbon pool (for more accurate mass under germination)
        #shoot_mass + root_mass + carbon.pool
        #FIXME handling None
        #shoot_mass + root_mass
        0
    end ~ track(u"g")

    # this will only be used for total leaf area adjustment.
    # If the individual leaf thing works out this will be deleted.
    potential_carbon_demand(potential_leaf_area_increase, SLA=200u"cm^2/g") => begin
        # Just a mocking value for now. Need to find a more mechanistic way to simulate change in SLA YY
        # SK 8/20/10: changed it to 200 cm2/g based on data from Kim et al. (2007) EEB
        # units are biomass not carbon
        leaf_mass_demand = potential_leaf_area_increase / SLA
        # potential_carbon_demand = carbon_demand # for now only carbon demand for leaf is calculated.
        leaf_mass_demand
    end ~ track(u"g")
end
