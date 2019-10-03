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
    phenology(context, calendar, weather, sun, soil): pheno ~ ::Phenology

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
    nodal_units(nu, pheno, primordia, germinated=pheno.germinated, dead=pheno.dead, l=pheno.leaves_initiated): nu => begin
        if isempty(nu)
            [produce(NodalUnit, phenology=pheno, rank=i) for i in 1:primordia]
        elseif germinated && !dead
            [produce(NodalUnit, phenology=pheno, rank=i) for i in (length(nu)+1):l]
        end
    end ~ produce::NodalUnit

    #TODO find a better place?
    planting_density: PD => 55 ~ preserve(u"m^-2", parameter)
end
