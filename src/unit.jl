using Unitful: Unitful, Units, Quantity, @u_str
export @u_str

unitfy(::Nothing, u) = nothing
unitfy(::Nothing, ::Nothing) = nothing
unitfy(::Missing, u) = missing
unitfy(::Missing, ::Nothing) = missing
unitfy(v, ::Nothing) = v
unitfy(v::Number, u::Units) = Quantity(v, u)
unitfy(v::Array, u::Units) = Quantity.(v, u)
unitfy(v::Tuple, u::Units) = Quantity.(v, u)
unitfy(v::Quantity, u::Units) = Unitful.uconvert(u, v)
unitfy(v::Array{<:Union{Quantity,Missing}}, u::Units) = Unitful.uconvert.(u, v)
unitfy(v::Tuple{Vararg{<:Union{Quantity,Missing}}}, u::Units) = Unitful.uconvert.(u, v)

deunitfy(v) = v
deunitfy(v::Quantity) = Unitful.ustrip(v)
deunitfy(v::Array) = deunitfy.(v)
deunitfy(v::Tuple) = deunitfy.(v)
deunitfy(v, u) = deunitfy(unitfy(v, u))

promoteunit(u...) = Unitful.promote_unit(filter(!isnothing, u)...)
promoteunit(::Nothing) = nothing
promoteunit() = nothing

hasunit(v::Units) = !Unitful.isunitless(v)
hasunit(::Nothing) = false

using DataFrames: DataFrame, DataFrames
unitfy(df::DataFrame, U::Vector) = begin
    r = DataFrame()
    f(c, u::Units) = unitfy.(c, u)
    f(c, u) = u.(c)
    f(c, ::Nothing) = c
    for (n, c, u) in zip(propertynames(df), eachcol(df), U)
        r[!, n] = f(c, u)
    end
    r
end
unitfy(df::DataFrame) = begin
    p = r"(.+)\(([^\(\)]+)\)$"
    M = match.(p, names(df))
    n(m::RegexMatch) = m.match => strip(m.captures[1])
    n(m) = nothing
    N = filter(!isnothing, n.(M))
    isempty(N) && return df
    u(m::RegexMatch) = begin
        s = m.captures[2]
        e = startswith(s, ":") ? Symbol(s[2:end]) : :(@u_str($s))
        eval(e)
    end
    u(m) = nothing
    U = u.(M)
    DataFrames.rename(unitfy(df, U), N...)
end

export unitfy, deunitfy
