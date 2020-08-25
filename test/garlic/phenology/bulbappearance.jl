@system BulbAppearance(Stage, FloralInitiation) begin
    bulb_appearable(floral_initiateable) ~ flag

    #HACK bulbing used to begin one phyllochron after floral initiation in bolting cultivars of garlic, see Meredith 2008
    bulb_appeared(floral_initiated) ~ flag

    bulb_appearing(bulb_appearable & !bulb_appeared) ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     print(f"* Bulbing: time = {self.time}, GDDsum = {GDD_sum}")
end
