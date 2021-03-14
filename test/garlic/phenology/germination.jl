@system Germination(Stage) begin
    planting_date ~ hold
    #HACK: can't mixin Emergence here due to cyclic dependency
    begin_from_emergence ~ hold

    GR_max: maximum_germination_rate => 0.45 ~ preserve(u"d^-1", parameter)

    germination(r=GR_max, β=BF.ΔT) => begin
        #FIXME prevent extra accumulation after it's `over`
        r * β
    end ~ accumulate(when=germinating)

    germinateable(planting_date, t=calendar.time) => (t >= planting_date) ~ flag
    germinated(germination, germinateable, begin_from_emergence) => (germination >= 0.5 || (germinateable && begin_from_emergence)) ~ flag
    germinating(germinateable & !germinated) ~ flag

    #FIXME postprocess similar to @produce?
    # finish(GDD_sum="pheno.gdd_recorder.rate", t="context.clock.time", dt="context.clock.step") => begin
    #     dt = dt * 24 * 60 # per min
    #     println("* Germinated: time = $t, GDDsum = $GDD_sum, time step (min) = $dt")
    # end ~ ?
end
