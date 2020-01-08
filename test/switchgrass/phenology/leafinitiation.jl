@system LeafInitiation(Stage, Germination, FloralInitiation) begin
    initial_leaves => 0 ~ preserve::Int(parameter)

    maximum_leaf_initiation_rate: LIR_max => 0.20 ~ preserve(u"d^-1", parameter)

    leaf_initiation(r=LIR_max, β=BF.ΔT, leaf_initiating) => begin
        leaf_initiating ? r * β : zero(r)
    end ~ accumulate
    leaves_initiated(n0=initial_leaves, n1=leaf_initiation) => floor(n0 + n1) ~ track::Int

    leaf_initiateable(germinated) ~ flag
    leaf_initiated(floral_initiated) ~ flag
    leaf_initiating(a=leaf_initiateable, b=leaf_initiated) => (a && !b) ~ flag
end
