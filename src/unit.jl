import Unitful: Unitful, Units, Quantity, uconvert, ustrip, @u_str
export @u_str

unitfy(::Nothing, u) = nothing
unitfy(::Nothing, ::Nothing) = nothing
unitfy(::Missing, u) = missing
unitfy(::Missing, ::Nothing) = missing
unitfy(v, ::Nothing) = v
unitfy(v::Number, u::Units) = Quantity(v, u)
unitfy(v::Array, u::Units) = Quantity.(v, u)
unitfy(v::Tuple, u::Units) = Quantity.(v, u)
unitfy(v::Quantity, u::Units) = uconvert(u, v)
unitfy(v::Array{<:Union{Quantity,Missing}}, u::Units) = uconvert.(u, v)
unitfy(v::Tuple{Vararg{<:Union{Quantity,Missing}}}, u::Units) = uconvert.(u, v)

deunitfy(v) = v
deunitfy(v::Quantity) = ustrip(v)
deunitfy(v::Array) = deunitfy.(v)
deunitfy(v::Tuple) = deunitfy.(v)
deunitfy(v, u) = deunitfy(unitfy(v, u))

import DataFrames: DataFrame, DataFrames
unitfy(df::DataFrame, U::Vector) = begin
    r = DataFrame()
    for (n, c, u) in zip(propertynames(df), eachcol(df), U)
        r[!, n] = unitfy.(c, u)
    end
    r
end
unitfy(df::DataFrame) = begin
    p = r"(.+)\(([^\(\)]+)\)$"
    M = match.(p, names(df))
    u(m::RegexMatch) = eval(:(@u_str($(m.captures[2]))))
    u(m) = nothing
    U = u.(M)
    n(m::RegexMatch) = m.match => strip(m.captures[1])
    n(m) = nothing
    N = filter(!isnothing, n.(M))
    DataFrames.rename(unitfy(df, U), N...)
end

export unitfy, deunitfy
