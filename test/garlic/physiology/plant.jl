@system Plant(
    Mass,
    Area,
    Count,
    Ratio,
    Carbon,
    #Nitrogen,
    Water,
    Weight,
    Photosynthesis
) begin
    weather(context) ~ ::Weather
    sun(context, weather) ~ ::Sun
    soil(context) ~ ::Soil
    pheno(context, weather, sun, soil): phenology ~ ::Phenology

    primordia => 5 ~ preserve::Int(parameter)

    #bulb => begin end ~ produce::Bulb

    #scape => begin end ~ produce::Scape

    root(root, pheno, emerging=pheno.emerging) => begin
        if isempty(root)
            if emerging
                #TODO import_carbohydrate(soil.total_root_weight)
                produce(Root, phenology=pheno)
            end
        end
    end ~ produce::Root

    #TODO pass PRIMORDIA as initial_leaves
    NU(NU, pheno, primordia, germinated=pheno.germinated, dead=pheno.dead, l=pheno.leaves_initiated): nodal_units => begin
        if germinated
            if isempty(NU)
                [produce(NodalUnit, phenology=pheno, rank=i) for i in 1:primordia]
            elseif !dead
                [produce(NodalUnit, phenology=pheno, rank=i) for i in (length(NU)+1):l]
            end
        end
    end ~ produce::NodalUnit

    #TODO find a better place?
    PD: planting_density => 55 ~ preserve(u"m^-2", parameter)
    DAP(pheno.DAP): day_after_planting ~ track::Int
end

@system GarlicModel(Plant, Controller)
