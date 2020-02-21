@system ScapeGrowth(Stage, LeafAppearance, FloralInitiation) begin
    #HACK: can't mixin ScapeRemoval/FlowerAppearance due to cyclic dependency
    scape_removed ~ hold
    flower_appeared ~ hold

    #HACK use LTAR
    SR_max(LTAR_max): maximum_scaping_rate => LTAR_max ~ track(u"d^-1")

    scape(r=SR_max, β=BF.ΔT, scaping) => begin
        scaping ? r * β : zero(r)
    end ~ accumulate

    scapeable(l=leaf_appeared, f=floral_initiated) => (l && f) ~ flag
    scaped(s=scape_removed, f=flower_appeared) => (s || f) ~ flag
    scaping(a=scapeable, b=scaped) => (a && !b) ~ flag
end

@system ScapeAppearance(Stage, ScapeGrowth) begin
    scape_appearable(scapeable) ~ flag
    scape_appeared(scape, scape_removed) => (scape >= 3.0 && !scape_removed) ~ flag
    scape_appearing(a=scape_appearable, b=scape_appeared) => (a && !b) ~ flag

    # def finish(self):
    #     print(f"* Scape Tip Visible: time = {self.time}, leaves = {self.pheno.leaves_appeared} / {self.pheno.leaves_initiated}")
end

@system ScapeRemoval(Stage, ScapeGrowth, ScapeAppearance) begin
    #FIXME handling default (non-removal) value?
    scape_removal_date => nothing ~ preserve::ZonedDateTime(optional, parameter)

    scape_removeable(scape_appeared) ~ flag
    scape_removed(scape_removal_date, t=context.calendar.time) => begin
        isnothing(scape_removal_date) ? false : t >= scape_removal_date
    end ~ flag
    scape_removing(a=scape_appeared, b=scape_removed) => (a && !b) ~ flag

    # def finish(self):
    #     print(f"* Scape Removed and Bulb Maturing: time = {self.time}")
end

@system FlowerAppearance(Stage, ScapeGrowth) begin
    flower_appearable(scapeable) ~ flag
    flower_appeared(scape, scape_removed) => (scape >= 5.0 && !scape_removed) ~ flag
    flower_appearing(a=flower_appearable, b=flower_appeared) => (a && !b) ~ flag

    # def finish(self):
    #     print(f"* Inflorescence Visible and Flowering: time = {self.time}")
end

@system BulbilAppearance(Stage, ScapeGrowth) begin
    bulbil_appearable(scapeable) ~ flag
    bulbil_appeared(scape, scape_removed) => (scape >= 5.5 && !scape_removed) ~ flag
    bulbil_appearing(a=bulbil_appearable, b=bulbil_appeared) => (a && !b) ~ flag

    # def finish(self):
    #     print(f"* Bulbil and Bulb Maturing: time = {self.time}")
end
