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
    calendar(context) ~ ::Calendar
    weather(context, calendar) ~ ::Weather
    sun(context, calendar, weather) ~ ::Sun
    soil(context) ~ ::Soil
    pheno(context, calendar, weather, sun, soil): phenology ~ ::Phenology

    primordia => 5 ~ preserve::Int(parameter)

    #bulb => begin end ~ produce::Bulb

    #scape => begin end ~ produce::Scape

    root(pheno, emerging=pheno.emerging) => begin
        if emerging
            #TODO import_carbohydrate(soil.total_root_weight)
            produce(Root, phenology=pheno)
        end
    end ~ produce::Root

    #TODO pass PRIMORDIA as initial_leaves
    NU(NU, pheno, primordia, germinated=pheno.germinated, dead=pheno.dead, l=pheno.leaves_initiated): nodal_units => begin
        if germinated && !dead
            n = length(NU)
            if n == 0
                [produce(NodalUnit, phenology=pheno, rank=i) for i in 1:primordia]
            elseif n < l
                [produce(NodalUnit, phenology=pheno, rank=i) for i in (n+1):l]
            end
        end
    end ~ produce::NodalUnit[]

    #TODO find a better place?
    PD: planting_density => 55 ~ preserve(u"m^-2", parameter)
    DAP(pheno.DAP): day_after_planting ~ track::Int
end

@system Model(Plant, Controller)
