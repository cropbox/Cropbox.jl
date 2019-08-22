@system FloralInitiation(Stage) begin
    critical_photoperiod: critPPD => 12 ~ preserve(u"hr", parameter)

    ready("pheno.germination.over") ~ flag

    #FIXME: implement Sun
    over(; day_length="pheno.weather.sun.day_length", critPPD) => begin
        #FIXME solstice consideration is broken (flag turns false after solstice) and maybe unnecessary
        # w = self.pheno.weather
        # solstice = w.time.tz.localize(datetime.datetime(w.time.year, 6, 21))
        # # no MAX_LEAF_NO implied unlike original model
        # return w.time <= solstice and w.day_length >= self.critical_photoperiod
        day_length >= critPPD
    end ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     print(f"* Floral initiation: time = {self.time}, GDDsum = {GDD_sum}")
end
