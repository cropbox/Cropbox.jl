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

    @testset "application" begin
        include("lotka_volterra.jl")
        include("pheno/estimator.jl")
        include("gasexchange/runtests.jl")
        include("root/runtests.jl")
        include("soil/soil.jl")
        include("garlic/runtests.jl")
    end
end
