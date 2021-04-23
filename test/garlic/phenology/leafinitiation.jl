@system LeafInitiation(Stage, Germination, FloralInitiation) begin
    SD: storage_days => 100 ~ preserve(u"d", parameter)
    ST: storage_temperature => 5 ~ preserve(u"°C", parameter)
    #FIXME: ThermalTime only accepts override of track, not preserve
    STP(ST): storage_tempreature_proxy ~ track(u"°C")
    SBF(context, T=STP, To=T_opt', Tx=T_ceil'): storage_beta_function ~ ::BetaFunction
    ILN: initial_leaves_at_harvest => 4 ~ preserve::int(parameter)
    ILS(LIR_max, β=SBF.ΔT, SD): initial_leaves_during_storage => begin
        LIR_max * β * SD
    end ~ preserve::int(round=:floor)
    initial_leaves(ILN, ILS) => ILN + ILS ~ preserve::int

    LIR_max: maximum_leaf_initiation_rate => 0.20 ~ preserve(u"d^-1", parameter)

    leaf_initiation(r=LIR_max, β=BF.ΔT) => r*β ~ accumulate(when=leaf_initiating)

    #HACK original garlic model assumed leaves are being initiated when the seeds are sown
    #HACK maize model model assumed leaf initiation begins when germination is over
    leaf_initiateable(germinated) ~ flag

    # for maize
    #leaf_initiated(pheno.tassel_initiation.over) ~ flag
    # for garlic
    leaf_initiated(floral_initiated) ~ flag

    leaf_initiating(leaf_initiateable & !leaf_initiated) ~ flag

    # no MAX_LEAF_NO implied unlike original model
    leaves_initiated(initial_leaves, leaf_initiation) => begin
        initial_leaves + leaf_initiation
    end ~ track::int(round=:floor)
end
