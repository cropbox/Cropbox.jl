@system LeafAppearance(Stage, Germination, Emergence, LeafInitiation) begin
    LTARa_max: maximum_leaf_tip_appearance_rate_asymptote => 0.4421 ~ preserve(u"d^-1", parameter)
    _SDm => 117.7523 ~ preserve(u"d", parameter)
    _k => 0.0256 ~ preserve(u"d^-1", parameter)
    LTAR_max(LTARa_max, SD, _SDm, _k): maximum_leaf_tip_appearance_rate => begin
        LTARa_max / (1 + exp(-k * (SD - SDm)))
    end ~ preserve(u"d^-1", parameter)

    leaf_tip_appearance(r=LTAR_max, β=BF.ΔT) => r*β ~ accumulate(when=leaf_appearing)

    leaf_appearable(emerged) ~ flag
    leaf_appeared(leaves_appeared, leaves_initiated) => begin
        #HACK ensure leaves are initiated
        leaves_appeared >= leaves_initiated > 0
    end ~ flag
    leaf_appearing(leaf_appearable & !leaf_appeared) ~ flag

    #HACK set initial leaf appearance to 1, not 0, to better describe stroage effect (2016-11-14: KDY, SK, JH)
    initial_leaf_tip_appearance => 1 ~ track::int(when=begin_from_emergence & leaf_appearable)
    leaves_appeared(initial_leaf_tip_appearance, leaf_tip_appearance) => begin
        initial_leaf_tip_appearance + leaf_tip_appearance 
    end ~ track::int(round=:floor)
end
