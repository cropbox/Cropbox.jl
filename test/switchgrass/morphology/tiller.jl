@system Tiller begin
    index ~ ::Int(override) # preserve

    #FIXME: does it matter with dynamic tiller growth?
    primordia => 5 ~ preserve::Int(parameter)

    nodal_units(nu, pheno, primordia, germinated=pheno.germinated, dead=pheno.dead, l=pheno.leaves_initiated): nu => begin
        if isempty(nu)
            [produce(NodalUnit, phenology=pheno, rank=i) for i in 1:primordia]
        elseif germinated && !dead
            [produce(NodalUnit, phenology=pheno, rank=i) for i in (length(nu)+1):l]
        end
    end ~ produce::NodalUnit
end