@system Area begin
	nodal_units ~ hold
	planting_density ~ hold

	leaf_area(x=nodal_units["*"].leaf.area) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    green_leaf_area(x=nodal_units["*"].leaf.green_area) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    #TODO remove if unnecessary
    # active_leaf_ratio(green_leaf_area, leaf_area) => (green_leaf_area / leaf_area) ~ track

    leaf_area_index(green_leaf_area, planting_density): LAI => begin
        green_leaf_area * planting_density
	end ~ track(u"cm^2/m^2")

    # actualgreenArea is the green area of leaf growing under carbon limitation
	#SK 8/22/10: There appears to be no distinction between these two variables in the code.
    actual_green_leaf_area(green_leaf_area) => green_leaf_area ~ track(u"cm^2")

    senescent_leaf_area(x=nodal_units["*"].leaf.senescent_area) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    potential_leaf_area(x=nodal_units["*"].leaf.potential_area) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    potential_leaf_area_increase(x=nodal_units["*"].leaf.potential_area_increase) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    # calculate relative area increases for leaves now that they are updated
    #TODO remove if unnecessary
    # relative_leaf_area_increase(x=nodal_units["*"].leaf.releative_area_increase) => (isempty(x) ? 0. : sum(x)) ~ track(u"cm^2")

    #FIXME it doesn't seem to be 'actual' dropped leaf area
    # calculated dropped leaf area YY
    dropped_leaf_area(potential_leaf_area, green_leaf_area) => (potential_leaf_area - green_leaf_area) ~ track(u"cm^2")
end
