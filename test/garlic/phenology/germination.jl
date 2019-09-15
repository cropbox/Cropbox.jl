@system Germination(Stage) begin
    planting_date ~ hold
    #HACK: can't mixin Emergence here due to cyclic dependency
    begin_from_emergence ~ hold

    maximum_germination_rate: GR_max => 0.45 ~ preserve(u"d^-1", parameter)

    germination(GR_max, T, T_opt, T_ceil, germinating) => begin
        #FIXME prevent extra accumulation after it's `over`
        germinating ? GR_max * beta_thermal_func(T, T_opt, T_ceil) : 0u"d^-1"
    end ~ accumulate

    germinateable(planting_date, t=calendar.time) => (t >= planting_date) ~ flag
    germinated(germination, begin_from_emergence) => (germination >= 0.5 || begin_from_emergence) ~ flag
    germinating(a=germinateable, b=germinated) => (a && !b) ~ flag

    #FIXME postprocess similar to @produce?
    # finish(GDD_sum="pheno.gdd_recorder.rate", t="context.clock.tick", dt="context.clock.step") => begin
    #     dt = dt * 24 * 60 # per min
    #     println("* Germinated: time = $t, GDDsum = $GDD_sum, time step (min) = $dt")
    # end ~ ?
end
