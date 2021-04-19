@system ScapeGrowth(Stage, LeafAppearance, FloralInitiation) begin
    #HACK: can't mixin ScapeRemoval/FlowerAppearance due to cyclic dependency
    scape_removed ~ hold
    flower_appeared ~ hold

    #HACK use LTAR
    SR_max(LTAR_max): maximum_scaping_rate => LTAR_max ~ track(u"d^-1")

    scape(r=SR_max, β=BF.ΔT) => r*β ~ accumulate(when=scaping)

    scapeable(leaf_appeared & floral_initiated) ~ flag
    scaped(scape_removed | flower_appeared) ~ flag
    scaping(scapeable & !scaped) ~ flag
end

@system ScapeAppearance(Stage, ScapeGrowth) begin
    scape_appearable(scapeable) ~ flag
    scape_appeared(scape, scape_removed) => (scape >= 3.0 && !scape_removed) ~ flag
    scape_appearing(scape_appearable & !scape_appeared) ~ flag

    # def finish(self):
    #     print(f"* Scape Tip Visible: time = {self.time}, leaves = {self.pheno.leaves_appeared} / {self.pheno.leaves_initiated}")
end

@system ScapeRemoval(Stage, ScapeGrowth, ScapeAppearance) begin
    #FIXME handling default (non-removal) value?
    scape_removal_date => nothing ~ preserve::datetime(optional, parameter)

    scape_removeable(scape_appeared) ~ flag
    scape_removed(scape_removal_date, t=calendar.time) => begin
        isnothing(scape_removal_date) ? false : t >= scape_removal_date
    end ~ flag
    scape_removing(scape_appeared & !scape_removed) ~ flag

    # def finish(self):
    #     print(f"* Scape Removed and Bulb Maturing: time = {self.time}")
end

@system FlowerAppearance(Stage, ScapeGrowth) begin
    flower_appearable(scapeable) ~ flag
    flower_appeared(scape, scape_removed) => (scape >= 5.0 && !scape_removed) ~ flag
    flower_appearing(flower_appearable & !flower_appeared) ~ flag

    # def finish(self):
    #     print(f"* Inflorescence Visible and Flowering: time = {self.time}")
end

@system BulbilAppearance(Stage, ScapeGrowth) begin
    bulbil_appearable(scapeable) ~ flag
    bulbil_appeared(scape, scape_removed) => (scape >= 5.5 && !scape_removed) ~ flag
    bulbil_appearing(bulbil_appearable & !bulbil_appeared) ~ flag

    # def finish(self):
    #     print(f"* Bulbil and Bulb Maturing: time = {self.time}")
end
