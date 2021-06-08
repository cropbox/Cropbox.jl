using Cropbox
using Test

@testset "cropbox" begin
    @testset "framework" begin
        include("macro.jl")
        include("state.jl")
        include("system.jl")
        include("unit.jl")
        include("config.jl")
        include("graph.jl")
        include("util.jl")
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
