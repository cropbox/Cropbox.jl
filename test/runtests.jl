using Cropbox
using Test

include("system.jl")

@equation a() = 1
@equation b(a) = a + 1
@equation c(a, b) = a + b
@equation d(b) = b

# mutable struct MySystem <: System
#     context::System
#     parent::System
#     children::Vector{System}
#
#     a::Var
#     b::Var
#     c::Var
#     d::Var
#
#     function MySystem(;context, parent, children=System[])
#         s = new()
#         s.context = context
#         s.parent = parent
#         s.children = children
#         s.a = Var(s, a, Track; name=:a, init=1, time=s.context.clock.time)
#         s.b = Var(s, b, Track; name=:b, time=s.context.clock.time)
#         s.c = Var(s, c, Track; name=:c, time=s.context.clock.time)
#         s.d = Var(s, d, Accumulate; name=:d, time=s.context.clock.time)
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
    b: bb ~ track(time="context.clock.time")
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
# exp(x::Var) = exp(convert(Float64, x))
# print(exp(s.a))
