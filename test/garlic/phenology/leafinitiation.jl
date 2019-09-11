@system LeafInitiation(Stage, Germination, FloralInitiation) begin
    initial_leaves ~ hold

    maximum_leaf_initiation_rate: LIR_max => 0.20 ~ preserve(u"d^-1", parameter)

    leaf_initiation(LIR_max, T, T_opt, T_ceil, leaf_initiating) => begin
        leaf_initiating ? LIR_max * beta_thermal_func(T, T_opt, T_ceil) : 0u"d^-1"
    end ~ accumulate

    #HACK original garlic model assumed leaves are being initiated when the seeds are sown
    #HACK maize model model assumed leaf initiation begins when germination is over
    leaf_initiateable(germinated) ~ flag

    # for maize
    #leaf_initiated(x=pheno.tassel_initiation.over) ~ flag
    # for garlic
    leaf_initiated(floral_initiated) ~ flag

    leaf_initiating(a=leaf_initiateable, b=leaf_initiated) => (a && !b) ~ flag

    # no MAX_LEAF_NO implied unlike original model
    leaves_initiated(initial_leaves, leaf_initiation) => round(initial_leaves + leaf_initiation) ~ track::Int
end

@system LeafInitiationWithoutStorage(LeafInitiation) begin
    initial_leaves => 0 ~ preserve(parameter)
end

@system LeafInitiationWithStorage(LeafInitiation) begin
    storage_days: SD => 0 ~ preserve(u"d", parameter)
    storage_temperature: ST => 5 ~ preserve(u"°C", parameter)
    initial_leaves_at_harvest: ILN => 4 ~ preserve(parameter)
    initial_leaves_during_storage(LIR_max, ST, T_opt, T_ceil, SD): ILS => begin
        LIR_max * beta_thermal_func(ST, T_opt, T_ceil) * SD
    end ~ track
    initial_leaves(ILN, ILS) => ILN + ILS ~ track
end
