@system Scape(Stage) begin
    #HACK use LTAR
    maximum_scaping_rate(LTAR="pheno.leaf_appearance.maximum_leaf_tip_appearance_rate"): R_max => LTAR ~ preserve(u"d^-1", parameter)

    rate(R_max, T, T_opt, T_ceil) => begin
        R_max * beta_thermal_func(T, T_opt, T_ceil)
    end ~ accumulate

    ready(lo="pheno.leaf_appearance.over", fo="pheno.floral_initiation.over") => (lo && fo) ~ flag
    over(fo="pheno.flowering.over", so="pheno.scape_removal.over") => (fo || so) ~ flag
end

#TODO: implement @systemproxy for convenience?

@system ScapeAppearance(Stage) begin
    scape ~ ::Scape(override)

    ready("scape.ready") ~ flag

    over(rate="scape.rate", ro="pheno.scape_removal.over") => begin
        rate >= 3.0 && !ro
    end ~ flag

    # def finish(self):
    #     print(f"* Scape Tip Visible: time = {self.time}, leaves = {self.pheno.leaves_appeared} / {self.pheno.leaves_initiated}")
end

@system ScapeRemoval(Stage) begin
    scape ~ ::Scape(override)

    #FIXME handling default (non-removal) value?
    scape_removal_date => nothing ~ preserve(parameter)

    ready("pheno.scape_appearance.over") ~ flag

    over(scape_removal_date, time="pheno.weather.calendar.time") => begin
        ismissing(scape_removal_date) ? false : time >= scape_removal_date
    end ~ flag

    # def finish(self):
    #     print(f"* Scape Removed and Bulb Maturing: time = {self.time}")
end

#TODO clean up naming (i.e. remove -ing prefix)
@system Flowering(Stage) begin
    scape ~ ::Scape(override)

    ready("scape.ready") ~ flag

    over(rate="scape.rate", so="pheno.scape_removal.over") => begin
        rate >= 5.0 && !so
    end ~ flag

    # def finish(self):
    #     print(f"* Inflorescence Visible and Flowering: time = {self.time}")
end

#TODO clean up naming (i.e. remove -ing prefix)
@system Bulbiling(Stage) begin
    scape ~ ::Scape(override)

    ready("scape.ready") ~ flag

    over(rate="scape.rate", so="pheno.scape_removal.over") => begin
        rate >= 5.5 && !so
    end ~ flag

    # def finish(self):
    #     print(f"* Bulbil and Bulb Maturing: time = {self.time}")
end
