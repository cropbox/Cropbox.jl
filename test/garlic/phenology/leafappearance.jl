@system LeafAppearance(Stage, Germination, Emergence, LeafInitiation) begin
    LTARa_max: maximum_leaf_tip_appearance_rate_asymptote => 0.4421 ~ preserve(u"d^-1", parameter)
    LTAR_SDm => 117.7523 ~ preserve(u"d", parameter)
    LTAR_k => 0.0256 ~ preserve(parameter)
    LTAR_max(asym=LTARa_max, x=SD, x_m=LTAR_SDm, k=LTAR_k): maximum_leaf_tip_appearance_rate => begin
        asym / (1 + exp(-k * Cropbox.deunitfy(x - x_m)))
    end ~ preserve(u"d^-1", parameter)

    leaf_tip_appearance(r=LTAR_max, β=BF.ΔT) => r*β ~ accumulate(when=leaf_appearing)

    leaf_appearable(emerged) ~ flag
    leaf_appeared(leaves_appeared, leaves_initiated) => begin
        #HACK ensure leaves are initiated
        leaves_appeared >= leaves_initiated > 0
    end ~ flag
    leaf_appearing(leaf_appearable & !leaf_appeared) ~ flag

    leaves_appeared(leaf_tip_appearance, leaf_appearable, begin_from_emergence) => begin
        #HACK set initial leaf appearance to 1, not 0, to better describe stroage effect (2016-11-14: KDY, SK, JH)
        initial_leaves = (begin_from_emergence && leaf_appearable) ? 1 : 0
        floor(Int, initial_leaves + leaf_tip_appearance)
    end ~ track::Int
end
