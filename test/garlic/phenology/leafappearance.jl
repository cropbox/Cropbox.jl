@system LeafAppearance include(Stage) begin
    maximum_leaf_tip_appearance_rate: R_max => 0.20 ~ preserve(u"d^-1", parameter)

    rate(R_max, T, T_opt, T_ceil) => begin
        R_max * beta_thermal_func(T, T_opt, T_ceil)
    end ~ accumulate

    ready(bfe="pheno.emergence.begin_from_emergence", eo="pheno.emergence.over", go="pheno.germination.over") => begin
        bfe ? eo : go
    end ~ flag

    over(leaves, initiated_leaves="pheno.leaf_initiation.leaves") => begin
        #HACK ensure leaves are initiated
        leaves >= initiated_leaves > 0
    end ~ flag

    leaves(rate, ready, bfe="pheno.emergence.begin_from_emergence") => begin
        #HACK set initial leaf appearance to 1, not 0, to better describe stroage effect (2016-11-14: KDY, SK, JH)
        initial_leaves = (bfe && ready) ? 1 : 0
        round(initial_leaves + rate)
    end ~ track::Int
end
