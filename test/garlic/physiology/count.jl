@system Count begin
    pheno: phenology ~ hold
    NU: nodal_units ~ hold

    leaves_initiated(pheno.leaves_initiated) ~ track::Int
    leaves_appeared(pheno.leaves_appeared) ~ track::Int

    leaves_growing(x=NU["*"].leaf.growing) => sum(x) ~ track::Int
    leaves_mature(x=NU["*"].leaf.mature) => sum(x) ~ track::Int
    leaves_dropped(x=NU["*"].leaf.dropped) => sum(x) ~ track::Int
end
