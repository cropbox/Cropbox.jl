using Cropbox
using Test

gensystem(head, body) = begin
    alias = gensym()
    name, incl = Cropbox.parsehead(head)
    quote
        $(Cropbox.gensystem(alias, incl, body))
        $(esc(name)) = $(esc(alias))
    end
end
macro system(head, body)
    gensystem(head, body)
end

@testset "cropbox" begin
    include("system.jl")
    include("unit.jl")
    include("lotka_volterra.jl")
    include("root_structure.jl")
    include("photosynthesis.jl")
end
