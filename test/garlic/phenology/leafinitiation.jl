@system LeafInitiation begin
    initial_leaves => 0 ~ preserve(parameter)

    maximum_leaf_initiation_rate: R_max => 0.20 ~ preserve(u"d^-1", parameter)

    rate(R_max, T, T_opt, T_ceil) => begin
        R_max * beta_thermal_func(T, T_opt, T_ceil)
    end ~ accumulate

    #HACK original garlic model assumed leaves are being initiated when the seeds are sown
    #HACK maize model model assumed leaf initiation begins when germination is over
    ready(f="pheno.germination.over") => f ~ flag

    # for maize
    #over(f="pheno.tassel_initiation.over") => f ~ flag
    # for garlic
    over(f="pheno.floral_initiation.over") => f ~ flag

    # no MAX_LEAF_NO implied unlike original model
    leaves(initial_leaves, rate) => round(initial_leaves + rate) ~ track::Int
end

@system LeafInitiationWithStorage(Stage, LeafInitiation) begin
    storage_days: SD => 0 ~ preserve(u"d", parameter)
    storage_temperature: ST => 5 ~ preserve(u"°C", parameter)
    initial_leaves_at_harvest: ILN => 4 ~ preserve(parameter)
    initial_leaves_during_storage(R_max, ST, T_opt, T_ceil, SD): ILS => begin
        R_max * beta_thermal_func(ST, T_opt, T_ceil) * SD
    end ~ track
    initial_leaves(ILN, ILS) => ILN + ILS ~ track
end
