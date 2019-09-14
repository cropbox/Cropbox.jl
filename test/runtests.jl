using Cropbox
using Test

@testset "cropbox" begin
    include("system.jl")
    include("unit.jl")
    include("lotka_volterra.jl")
    include("root_structure.jl")
    include("photosynthesis.jl")
end
