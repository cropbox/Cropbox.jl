@system Mass(Trait) begin
    # seed weight g/seed
    initial_seed => 0.275 ~ preserve(u"g", parameter)

    #HACK carbon mass of seed is pulled in the reserve
    seed(initial_seed) => begin
        #FIXME carbon not ready yet
        #return self.initial_seed - self.p.carbon.reserve_from_seed
        initial_seed
    end ~ track(u"g")

    #stem(NU="p.nodal_units") => begin # for maize
    sheath(x="p.nodal_units[*].sheath.mass") => begin # for garlic
        # dt the addition of C_reserve here only serves to maintain a total for the mass. It could have just as easily been added to total mass.
        # C_reserve is added to stem here to represent soluble TNC, SK
        #sum(typeof(0.0u"g")[Cropbox.value!(nu.stem.mass) for nu in NU]) + self.p.carbon.reserve
        #sum(typeof(0.0u"g")[Cropbox.value!(nu.sheath.mass) for nu in NU]) + self.p.carbon.reserve
        #FIXME carbon not ready yet
        isempty(x) ? 0 : sum(x)
    end ~ track(u"g")

    initial_leaf(initial_seed, ratio="p.ratio.initial_leaf") => begin
        initial_seed * ratio
    end ~ track(u"g")

    # this is the total mass of active leaves that are not entirely dead (e.g., dropped).
    # It would be slightly greather than the green leaf mass because some senesced leaf area is included until they are complely aged (dead), SK
    active_leaf(NU="p.nodal_units", x="p.nodal_units[*].leaf.mass") => begin
        sum(typeof(0.0u"g")[Cropbox.value(nu.leaf.mass) for nu in NU if !Cropbox.value(nu.leaf.dropped)])
    end ~ track(u"g")
    #TODO: support complex composition (i.e. `!`(leaf.dropped)) in condition syntax?
    #active_leaf(x="p.nodal_units[*/!leaf.dropped].leaf.mass") => (isempty(x) ? 0 : sum(x)) ~ track(u"g")

    dropped_leaf(NU="p.nodal_units", x="p.nodal_units[*].leaf.mass") => begin
        sum(typeof(0.0u"g")[Cropbox.value(nu.leaf.mass) for nu in NU if Cropbox.value(nu.leaf.dropped)])
    end ~ track(u"g")
    #TODO: support more referencing options (i.e. "leaf.dropped") in condition syntax?
    #dropped_leaf(x="p.nodal_units[*/leaf.dropped].leaf.mass") => (isempty(x) ? 0 : sum(x)) ~ track(u"g")

    total_leaf(x="p.nodal_units[*].leaf.mass") => begin
        # this should equal to activeLeafMass + droppedLeafMass
        isempty(x) ? 0 : sum(x)
    end ~ track(u"g")

    leaf(total_leaf) => total_leaf ~ track(u"g")

    # for maize

    # ear("p.ear.mass") ~ track(u"g")

    # for garlic

    bulb => begin
        #FIXME handling None
        #self.p.bulb.mass
        0
    end ~ track(u"g")

    scape => begin
        #FIXME handling None
        #self.p.scape.mass
        0
    end ~ track(u"g")

    stalk => begin
        #FIXME inconsistency: stem vs. sheath
        #FIXME handling None
        #self.sheath + self.scape
        0
    end ~ track(u"g")

    root => begin
        #FIXME handling None
        #self.p.root.mass
        0
    end ~ track(u"g")

    shoot => begin
        # for maize
        #seed + stem + leaf + ear
        # for garlic
        #FIXME handling None
        #seed + stalk + leaf + bulb
        0
    end ~ track(u"g")

    total => begin
        #HACK include mobilized carbon pool (for more accurate mass under germination)
        #shoot + root + p.carbon.pool
        #FIXME handling None
        #shoot + root
        return 0
    end ~ track(u"g")

    # this will only be used for total leaf area adjustment.
    # If the individual leaf thing works out this will be deleted.
    potential_carbon_demand(la="p.area.potential_leaf_increase", SLA=200u"cm^2/g") => begin
        # Just a mocking value for now. Need to find a more mechanistic way to simulate change in SLA YY
        # SK 8/20/10: changed it to 200 cm2/g based on data from Kim et al. (2007) EEB
        # units are biomass not carbon
        leaf_mass_demand = la / SLA
        # potential_carbon_demand = carbon_demand # for now only carbon demand for leaf is calculated.
        leaf_mass_demand
    end ~ track(u"g")
end
