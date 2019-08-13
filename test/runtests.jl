using Cropbox
using Test

macro system(name, block, options...)
    alias = gensym()
    quote
        $(Cropbox.gensystem(alias, block, options...))
        $(esc(name)) = $(esc(alias))
    end
end

@testset "cropbox" begin
    include("system.jl")
    include("lotka_volterra.jl")
    include("root_structure.jl")
end

@equation a() = 1
@equation b(a) = a + 1
@equation c(a, b) = a + b
@equation d(b) = b

@system MySystem begin
    a ~ track
    b ~ track
    c ~ track
    d: dd ~ accumulate
end

@system ASystem begin
    a ~ track
    b: bb ~ track(time="context.clock.time")
    ccc(a, b): c => a+b ~ track(unit="cm")
    cccc(a=1, b=2): cc => a+b ~ track
    d(a, b) => begin
      a + b
    end ~ track(cyclic)
    e(a) => a ~ accumulate(init=0)
end

s = instance(MySystem)
advance!(s.context)
