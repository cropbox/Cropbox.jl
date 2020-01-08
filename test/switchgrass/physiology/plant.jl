@system Plant(
    # Mass,
    # Area,
    # Count,
    # Ratio,
    # Carbon,
    # #Nitrogen,
    # Water,
    # Weight,
    # Photosynthesis
) begin
    calendar(context) ~ ::Calendar
    weather(context, calendar) ~ ::Weather
    sun(context, calendar, weather) ~ ::Sun
    soil(context) ~ ::Soil
    phenology(context, calendar, weather, sun, soil): pheno ~ ::Phenology

    root(root, pheno, emerging=pheno.emerging) => begin
        if isempty(root)
            if emerging
                #TODO import_carbohydrate(soil.total_root_weight)
                produce(Root, phenology=pheno)
            end
        end
    end ~ produce::Root
    
    tillers(tillers, pheno, growing=pheno.growing, l=pheno.leaves_initiated) => begin
        [produce(Tiller, phenology=pheno, index=i) for i in (length(tillers)+1):l]
    end ~ produce::Tiller

    #TODO find a better place?
    planting_density: PD => 55 ~ preserve(u"m^-2", parameter)
end

@system Switchgrass(Plant, Controller)
