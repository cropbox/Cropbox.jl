using Cropbox
using Test

@testset "cropbox" begin
    @testset "framework" begin
        include("framework/macro.jl")
        include("framework/state.jl")
        include("framework/system.jl")
        include("framework/unit.jl")
        include("framework/config.jl")
        include("framework/graph.jl")
        include("framework/util.jl")
    end

    @testset "examples" begin
        include("examples/lotka_volterra.jl")
        include("examples/pheno.jl")
        include("examples/gasexchange.jl")
        include("examples/root.jl")
        include("examples/soil.jl")
        include("examples/garlic.jl")
    end
end
