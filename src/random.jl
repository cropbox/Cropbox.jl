using Distributions: Distribution, Normal
#HACK: Measurements.jl causes weird StackOverFlow error when used with other packages (i.e. Plots, UnicodePlots)
#HACK: not exactly same, but maybe related with https://github.com/PumasAI/Pumas.jl/issues/609
#import Measurements
#using Measurements: Measurement, ±
using Unitful: Quantity

#HACK: define own Measurement just for supporting ± syntax
struct Measurement{T} <: Number
    val::T
    err::T
end

measurement(a::Quantity, b::Quantity) = begin
    u = Unitful.promote_unit(Unitful.unit(a), Unitful.unit(b))
    measurement(deunitfy(a, u), deunitfy(b, u)) * u
end
measurement(a, b) = Measurement(promote(a, b)...)

const ± = measurement
export ±

Base.show(io::IO, m::Measurement) = print(io, "$(m.val) ± $(m.err)")

sample(v::Distribution) = rand(v)
sample(v::Measurement) = rand(Normal(v.val, v.err))
sample(v::Quantity{<:Measurement}) = unitfy(sample(deunitfy(v)), unittype(v))
sample(v) = v
