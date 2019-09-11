@system LeafAppearance(Stage, Germination, Emergence, LeafInitiation) begin
    maximum_leaf_tip_appearance_rate: LTAR_max => 0.20 ~ preserve(u"d^-1", parameter)

    leaf_tip_appearance(LTAR_max, T, T_opt, T_ceil, leaf_appearing) => begin
        leaf_appearing ? LTAR_max * beta_thermal_func(T, T_opt, T_ceil) : 0u"d^-1"
    end ~ accumulate

    leaf_appearable(emerged) ~ flag
    leaf_appeared(leaves_appeared, leaves_initiated) => begin
        #HACK ensure leaves are initiated
        leaves_appeared >= leaves_initiated > 0
    end ~ flag
    leaf_appearing(a=leaf_appearable, b=leaf_appeared) => (a && !b) ~ flag

    leaves_appeared(leaf_tip_appearance, leaf_appearable, begin_from_emergence) => begin
        #HACK set initial leaf appearance to 1, not 0, to better describe stroage effect (2016-11-14: KDY, SK, JH)
        initial_leaves = (begin_from_emergence && leaf_appearable) ? 1 : 0
        round(initial_leaves + leaf_tip_appearance)
    end ~ track::Int
end
