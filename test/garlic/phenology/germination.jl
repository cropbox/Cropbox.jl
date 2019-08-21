@system Germination include(Stage) begin
    maximum_germination_rate: R_max => 0.45 ~ preserve(u"d^-1", parameter)

    rate(R_max, T, T_opt, T_ceil, ing) => begin
        #FIXME prevent extra accumulation after it's `over`
        ing ? R_max * beta_thermal_func(T, T_opt, T_ceil) : 0u"d^-1"
    end ~ accumulate

    over(rate, f="pheno.emergence.begin_from_emergence") => (rate >= 0.5 || f) ~ flag

    #FIXME postprocess similar to @produce?
    # finish(GDD_sum="pheno.gdd_recorder.rate", t="context.clock.tick", dt="context.clock.step") => begin
    #     dt = dt * 24 * 60 # per min
    #     println("* Germinated: time = $t, GDDsum = $GDD_sum, time step (min) = $dt")
    # end ~ ?
end
