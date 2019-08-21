@system Bulbing include(Stage) begin
    ready(f="pheno.floral_initiation.ready") => f ~ flag

    #HACK bulbing used to begin one phyllochron after floral initiation in bolting cultivars of garlic, see Meredith 2008
    over(f="pheno.floral_initiation.over") => f ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     print(f"* Bulbing: time = {self.time}, GDDsum = {GDD_sum}")
end
