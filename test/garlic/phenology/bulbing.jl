@system Bulbing(Stage) begin
    ready(x=pheno.floral_initiation.ready) ~ flag

    #HACK bulbing used to begin one phyllochron after floral initiation in bolting cultivars of garlic, see Meredith 2008
    over(x=pheno.floral_initiation.over) ~ flag

    # #FIXME postprocess similar to @produce?
    # def finish(self):
    #     GDD_sum = self.pheno.gdd_recorder.rate
    #     print(f"* Bulbing: time = {self.time}, GDDsum = {GDD_sum}")
end
