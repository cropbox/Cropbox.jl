@system Plant(
    Mass,
    Area,
    Count,
    Ratio,
    Photosynthesis,
    #Carbon,
    #Nitrogen,
    Water,
    Weight
) begin
    weather(context) => Weather(; context=context) ~ ::Weather
    soil(context) => Soil(; context=context) ~ ::Soil

    phenology(context, weather, soil): pheno => Phenology(; context=context, weather=weather, soil=soil) ~ ::Phenology

    primordia => 5 ~ preserve(parameter)

    bulb => begin end ~ produce

    scape => begin end ~ produce

    root(root, emerging=pheno.emerging) => begin
        if isempty(root)
            if emerging
                #TODO import_carbohydrate(soil.total_root_weight)
                produce(Root, plant=self)
            end
        end
    end ~ produce

    #TODO pass PRIMORDIA as initial_leaves
    nodal_units(nu, pheno, primordia, germinated=pheno.germinated, dead=pheno.dead, l=pheno.leaves_initiated): nu => begin
        if isempty(nu)
            [produce(NodalUnit, phenology=pheno, rank=i) for i in 1:primordia]
        elseif germinated && !dead
            [produce(NodalUnit, phenology=pheno, rank=i) for i in (length(nu)+1):l]
        end
    end ~ produce

    #TODO find a better place?
    planting_density: PD => 55 ~ preserve(u"m^-2", parameter)
end
