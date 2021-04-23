@system Mass begin
    pheno: phenology ~ hold
    NU: nodal_units ~ hold

    initial_leaf_ratio ~ hold
    potential_leaf_area_increase ~ hold

    shoot_carbon ~ hold
    root_carbon ~ hold
    leaf_carbon ~ hold
    sheath_carbon ~ hold
    scape_carbon ~ hold
    bulb_carbon ~ hold

    # seed weight g/seed
    initial_seed_mass => 0.275 ~ preserve(u"g", parameter)

    # 10% available
    seed_mass_export_limit => 10 ~ preserve(u"percent/d")
    seed_mass_export_rate(seed_mass, seed_mass_export_limit, β=pheno.BF.ΔT) => begin
        # reserved in the propagule (e.g., starch in endosperm of seeds)
        #HACK ratio should depend on growth stage, but fix it for now
        T_effect = β
        seed_mass * T_effect * seed_mass_export_limit
    end ~ track(u"g/d")

    #HACK carbon mass of seed is pulled in the reserve
    seed_mass(seed_mass_export_rate) => begin
        -seed_mass_export_rate
    end ~ accumulate(init=initial_seed_mass, u"g")

    #stem(x=NU["*"].stem.mass) => begin # for maize
    total_sheath_mass(x=NU["*"].sheath.mass) => begin # for garlic
        # dt the addition of C_reserve here only serves to maintain a total for the mass. It could have just as easily been added to total mass.
        # C_reserve is added to stem here to represent soluble TNC, SK
        #sum(typeof(0.0u"g")[nu.stem.mass' for nu in NU]) + self.p.carbon.reserve
        #sum(typeof(0.0u"g")[nu.sheath.mass' for nu in NU]) + self.p.carbon.reserve
        #FIXME carbon not ready yet
        sum(x)
    end ~ track(u"g")

    initial_leaf_mass(initial_seed_mass, initial_leaf_ratio) => begin
        initial_seed_mass * initial_leaf_ratio
    end ~ track(u"g")

    # this is the total mass of active leaves that are not entirely dead (e.g., dropped).
    # It would be slightly greather than the green leaf mass because some senesced leaf area is included until they are complely aged (dead), SK
    active_leaf_mass(NU #=, x=NU["*"].leaf.mass =#) => begin
        sum(typeof(0.0u"g")[nu.leaf.mass' for nu in NU if !nu.leaf.dropped'])
    end ~ track(u"g")
    #TODO: support complex composition (i.e. `!`(leaf.dropped)) in condition syntax?
    #active_leaf_mass(x=NU["*/!leaf.dropped"].leaf.mass) => sum(x) ~ track(u"g")

    dropped_leaf_mass(NU #=, x=NU["*"].leaf.mass =#) => begin
        sum(typeof(0.0u"g")[nu.leaf.mass' for nu in NU if nu.leaf.dropped'])
    end ~ track(u"g")
    #TODO: support more referencing options (i.e. "leaf.dropped") in condition syntax?
    #dropped_leaf(x=NU["*/leaf.dropped"].leaf.mass) => sum(x) ~ track(u"g")

    total_leaf_mass(x=NU["*"].leaf.mass) => begin
        # this should equal to activeLeafMass + droppedLeafMass
        sum(x)
    end ~ track(u"g")

    # for maize

    # ear_mass(ear.mass) ~ track(u"g")

    # for garlic

    root_mass(root_carbon) ~ accumulate(u"g")
    leaf_mass(leaf_carbon) ~ accumulate(u"g")
    sheath_mass(sheath_carbon) ~ accumulate(u"g")
    scape_mass(scape_carbon) ~ accumulate(u"g")
    bulb_mass(bulb_carbon) ~ accumulate(u"g")

    stalk_mass(sheath_mass, scape_mass) => begin
        #FIXME inconsistency: stem vs. sheath
        sheath_mass + scape_mass
    end ~ track(u"g")

    #shoot_mass(shoot_carbon) => begin
    shoot_mass(seed_mass, stalk_mass, leaf_mass, bulb_mass) => begin
        # for maize
        #seed_mass + stem_mass + leaf_mass + ear_mass
        # for garlic
        seed_mass + stalk_mass + leaf_mass + bulb_mass
    end ~ track(u"g")

    total_mass(shoot_mass, root_mass) => begin
        #HACK include mobilized carbon pool (for more accurate mass under germination)
        #shoot_mass + root_mass + carbon.pool
        shoot_mass + root_mass
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
