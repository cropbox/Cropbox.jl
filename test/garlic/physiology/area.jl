@system Area begin
    NU: nodal_units ~ hold
    PD: planting_density ~ hold

    leaf_area(x=NU["*"].leaf.area) => sum(x) ~ track(u"cm^2")

    green_leaf_area(x=NU["*"].leaf.green_area) => sum(x) ~ track(u"cm^2")

    green_leaf_ratio(green_leaf_area, leaf_area) => begin
        iszero(leaf_area) ? 0. : (green_leaf_area / leaf_area)
    end ~ track

    LAI(green_leaf_area, PD): leaf_area_index => begin
        green_leaf_area * PD
    end ~ track

    # actualgreenArea is the green area of leaf growing under carbon limitation
    #SK 8/22/10: There appears to be no distinction between these two variables in the code.
    actual_green_leaf_area(green_leaf_area) => green_leaf_area ~ track(u"cm^2")

    senescent_leaf_area(x=NU["*"].leaf.senescent_area) => sum(x) ~ track(u"cm^2")

    potential_leaf_area(x=NU["*"].leaf.potential_area) => sum(x) ~ track(u"cm^2")

    potential_leaf_area_increase(x=NU["*"].leaf.potential_area_increase) => sum(x) ~ track(u"cm^2")

    # calculate relative area increases for leaves now that they are updated
    #TODO remove if unnecessary
    # relative_leaf_area_increase(x=NU["*"].leaf.relative_area_increase) => sum(x) ~ track(u"cm^2")

    #FIXME it doesn't seem to be 'actual' dropped leaf area
    # calculated dropped leaf area YY
    dropped_leaf_area(potential_leaf_area, green_leaf_area) => (potential_leaf_area - green_leaf_area) ~ track(u"cm^2")
end
