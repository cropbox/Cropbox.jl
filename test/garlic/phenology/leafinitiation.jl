@system LeafInitiation(Stage, Germination, FloralInitiation) begin
    initial_leaves ~ hold

    maximum_leaf_initiation_rate: LIR_max => 0.20 ~ preserve(u"d^-1", parameter)

    leaf_initiation(r=LIR_max, β=BF.ΔT, leaf_initiating) => begin
        leaf_initiating ? r * β : zero(r)
    end ~ accumulate

    #HACK original garlic model assumed leaves are being initiated when the seeds are sown
    #HACK maize model model assumed leaf initiation begins when germination is over
    leaf_initiateable(germinated) ~ flag

    # for maize
    #leaf_initiated(pheno.tassel_initiation.over) ~ flag
    # for garlic
    leaf_initiated(floral_initiated) ~ flag

    leaf_initiating(a=leaf_initiateable, b=leaf_initiated) => (a && !b) ~ flag

    # no MAX_LEAF_NO implied unlike original model
    leaves_initiated(initial_leaves, leaf_initiation) => begin
        floor(Int, initial_leaves + leaf_initiation)
    end ~ track::Int
end

@system LeafInitiationWithoutStorage(LeafInitiation) begin
    initial_leaves => 0 ~ preserve::Int(parameter)
end

@system LeafInitiationWithStorage(LeafInitiation) begin
    storage_days: SD => 0 ~ preserve(u"d", parameter)
    storage_temperature: ST => 5 ~ preserve(u"°C", parameter)
    #FIXME: ThermalTime only accepts override of track, not preserve
    storage_tempreature_proxy(ST): STP ~ track(u"°C")
    storage_beta_function(context, T=STP, To=T_opt', Tx=T_ceil'): SBF ~ ::BetaFunction
    initial_leaves_at_harvest: ILN => 4 ~ preserve::Int(parameter)
    initial_leaves_during_storage(LIR_max, β=SBF.ΔT, SD): ILS => begin
        floor(Int, LIR_max * β * SD)
    end ~ preserve::Int
    initial_leaves(ILN, ILS) => ILN + ILS ~ preserve::Int
end
