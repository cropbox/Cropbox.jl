@system Emergence(Stage, Germination) begin
    #HACK: can't use self.pheno.leaf_appearance.maximum_leaf_tip_appearance_rate due to recursion
    maximum_emergence_rate: ER_max => 0.20 ~ preserve(u"d^-1", parameter)

    emergence_date => nothing ~ preserve::Union{ZonedDateTime,Nothing}(parameter)
    begin_from_emergence(emergence_date) => !isnothing(emergence_date) ~ preserve::Bool

    emergence(r=ER_max, T, T_opt, T_ceil, emerging) => begin
        emerging ? r * beta_thermal_func(T, T_opt, T_ceil) : zero(r)
    end ~ accumulate

    emergeable(germinated) ~ flag
    emerged(emergence, begin_from_emergence, emergence_date, t=calendar.time) => begin
        if begin_from_emergence
            t >= emergence_date
        else
            emergence >= 1.0
        end
    end ~ flag
    emerging(a=emergeable, b=emerged) => (a && !b) ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     T_grow = self.pheno.growing_temperature
    #     print(f"* Emergence: time = {self.time}, GDDsum = {GDD_sum}, Growing season T = {T_grow}")

    #     #HACK reset GDD tracker after emergence
    #     self.emerge_GDD = GDD_sum
    #     self.pheno.gdd_recorder.reset()
end
