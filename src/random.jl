import Distributions: Distribution, Normal
import Measurements
import Measurements: Measurement, ±
import Unitful: Quantity

sample(v::Distribution) = rand(v)
sample(v::Measurement) = rand(Normal(Measurements.value(v), Measurements.uncertainty(v)))
sample(v::Quantity{<:Measurement}) = sample(ustrip(v)) * unit(v)
sample(v) = v

export ±
