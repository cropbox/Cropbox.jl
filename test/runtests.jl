using Cropbox
using Test

include("system.jl")

a() = 1
b(a) = a + 1
c(a, b) = a + b
d(b) = b

# mutable struct MySystem <: System
#     context::System
#     parent::System
#     children::Vector{System}
#
#     a::Statevar
#     b::Statevar
#     c::Statevar
#     d::Statevar
#
#     function MySystem(;context, parent, children=System[])
#         s = new()
#         s.context = context
#         s.parent = parent
#         s.children = children
#         s.a = Statevar(s, a, Track; name=:a, init=1, time=s.context.clock.tick)
#         s.b = Statevar(s, b, Track; name=:b, time=s.context.clock.tick)
#         s.c = Statevar(s, c, Track; name=:c, time=s.context.clock.tick)
#         s.d = Statevar(s, d, Accumulate; name=:d, time=s.context.clock.tick)
#         s
#     end
# end

@system MySystem begin
    a ~ track(init=1)
    b ~ track
    c ~ track
    d: dd ~ accumulate
end

@system ASystem begin
    a ~ track
    b: bb ~ track(time="context.clock.tick")
    ccc(a, b): c => a+b ~ track(unit="cm")
    cccc(a=1, b=2): cc => a+b ~ track(init=0)
    d(a, b) => begin
      a + b
    end ~ track(cyclic)
    e(a) => a ~ accumulate(init=0)
end

s = instance(MySystem)
advance!(s.context)

# print(convert(Float64, s.a))
# print(promote(s.a, 1.0))
# print(s.a + 1)
#
# import Base: exp
# exp(v::Statevar) = exp(convert(Float64, v))
# print(exp(s.a))
