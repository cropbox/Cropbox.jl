@system Count begin
    pheno: phenology ~ hold
    NU: nodal_units ~ hold

    leaves_initiated(pheno.leaves_initiated) ~ track::int
    leaves_appeared(pheno.leaves_appeared) ~ track::int

    leaves_growing(x=NU["*"].leaf.growing) => sum(x) ~ track::int
    leaves_mature(x=NU["*"].leaf.mature) => sum(x) ~ track::int
    leaves_dropped(x=NU["*"].leaf.dropped) => sum(x) ~ track::int
end
