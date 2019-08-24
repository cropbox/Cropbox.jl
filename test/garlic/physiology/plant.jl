@system Plant begin
    weather => Weather(; context=context) ~ ::Weather(expose)
    soil => Soil(; context=context) ~ ::Soil(expose)

    phenology: pheno => Phenology(; context=context, plant=self, weather=weather, soil=soil) ~ ::Phenology
    photosynthesis => Photosynthesis(; context=context, plant=self) ~ ::Photosynthesis

    mass => Mass(; context=context, plant=self) ~ ::Mass
    area => Area(; context=context, plant=self) ~ ::Area
    count => Count(; context=context, plant=self) ~ ::Count
    ratio => Ratio(; context=context, plant=self) ~ ::Ratio
    #carbon => Carbon(; context=context, plant=self) ~ ::Carbon
    #nitrogen => Nitrogen(; context=context, plant=self) ~ ::Nitrogen
    water => Water(; context=context, plant=self) ~ ::Water

    weight => Weight(; context=context) ~ ::Weight

    primordia => 5 ~ preserve::Int(parameter)

    bulb => begin end ~ produce

    scape => begin end ~ produce

    root(root, emerging="pheno.emerging") => begin
        if isempty(root)
            if emerging
                #TODO import_carbohydrate(soil.total_root_weight)
                produce(Root, plant=self)
            end
        end
    end ~ produce

    #TODO pass PRIMORDIA as initial_leaves
    nodal_units(nu, primordia, germinating="pheno.germinating", dead="pheno.dead", l="pheno.leaves_initiated"): nu => begin
        if isempty(nu)
            nodal_units_products = [produce(NodalUnit, plant=self, rank=i) for i in 1:primordia]
        elseif !(germinating || dead)
            [produce(NodalUnit, plant=self, rank=i) for i in (length(nu)+1):l]
        end
    end ~ produce

    #TODO find a better place?
    planting_density => 55 ~ preserve(u"m^-2", parameter)
end
