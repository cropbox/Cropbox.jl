@system Count begin
    pheno: phenology ~ hold
    leaves ~ hold

    leaves_initiated(pheno.leaves_initiated) ~ track::Int
    leaves_appeared(pheno.leaves_appeared) ~ track::Int

    leaves_growing(x=leaves.growing) => sum(x) ~ track::Int
    leaves_mature(x=leaves.mature) => sum(x) ~ track::Int
    leaves_dropped(x=leaves.dropped) => sum(x) ~ track::Int
end
