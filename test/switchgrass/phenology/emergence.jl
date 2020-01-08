@system Emergence(Stage, Germination) begin
    #HACK: can't use self.pheno.leaf_appearance.maximum_leaf_tip_appearance_rate due to recursion
    maximum_emergence_rate: ER_max => 0.20 ~ preserve(u"d^-1", parameter)

    emergence(r=ER_max, β=BF.ΔT, emerging) => begin
        emerging ? r * β : zero(r)
    end ~ accumulate

    emergeable(germinated) ~ flag
    emerged(emergence) => emergence >= 1 ~ flag
    emerging(a=emergeable, b=emerged) => (a && !b) ~ flag
end
