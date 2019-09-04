@system Emergence(Stage) begin
    #HACK: can't use self.pheno.leaf_appearance.maximum_leaf_tip_appearance_rate due to recursion
    maximum_emergence_rate: R_max => 0.20 ~ preserve(u"d^-1", parameter)

    emergence_date => nothing ~ preserve(parameter)
    begin_from_emergence(emergence_date) => !isnothing(emergence_date) ~ preserve::Bool

    rate(R_max, T, T_opt, T_ceil) => begin
        R_max * beta_thermal_func(T, T_opt, T_ceil)
    end ~ accumulate

    ready("pheno.germination.over") ~ flag

    over(rate, begin_from_emergence, emergence_date, time="pheno.weather.calendar.time") => begin
        if begin_from_emergence
            time >= emergence_date
        else
            rate >= 1.0
        end
    end ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     T_grow = self.pheno.growing_temperature
    #     print(f"* Emergence: time = {self.time}, GDDsum = {GDD_sum}, Growing season T = {T_grow}")

    #     #HACK reset GDD tracker after emergence
    #     self.emerge_GDD = GDD_sum
    #     self.pheno.gdd_recorder.reset()
end
