using Unitful: Unitful, Units, Quantity, @u_str
export @u_str

unitfy(::Nothing, u) = nothing
unitfy(::Nothing, ::Nothing) = nothing
unitfy(::Missing, u) = missing
unitfy(::Missing, ::Nothing) = missing
unitfy(v, ::Nothing) = !hasunit(v) ? deunitfy(v) : error("unable to strip units: $v")
unitfy(v, ::Missing) = v
unitfy(v::Number, u::Units) = Quantity(v, u)
unitfy(v::Array, u::Units) = unitfy.(v, u)
unitfy(v::Tuple, u::Units) = unitfy.(v, u)
unitfy(v::Quantity, u::Units) = Unitful.uconvert(u, v)
unitfy(v::Array{<:Union{Quantity,Missing}}, u::Units) = unitfy.(v, u)
unitfy(v::Tuple{Vararg{Union{Quantity,Missing}}}, u::Units) = unitfy.(v, u)
unitfy(v, u) = u(v)
unitfy(v::V, ::Type{V}) where V = v

deunitfy(v) = v
deunitfy(v::Quantity) = Unitful.ustrip(v)
deunitfy(v::Array) = deunitfy.(v)
deunitfy(v::Tuple) = deunitfy.(v)
deunitfy(v, u) = deunitfy(unitfy(v, u))
deunitfy(v, ::Missing) = deunitfy(v)

promoteunit(u...) = Unitful.promote_unit(filter(!isnothing, u)...)
promoteunit(::Nothing) = nothing
promoteunit() = nothing

hasunit(v::Units) = !Unitful.isunitless(v)
hasunit(::Nothing) = false
hasunit(v) = hasunit(unittype(v))

using DataFrames: DataFrame, DataFrames
for f in (:unitfy, :deunitfy)
    @eval $f(df::DataFrame, U::Vector) = begin
        r = DataFrame()
        for (n, c, u) in zip(propertynames(df), eachcol(df), U)
            r[!, n] = $f.(c, u)
        end
        r
    end
end

import Dates
unitfy(df::DataFrame; kw...) = begin
    #HACK: default constructor for common types to avoid scope binding issue
    D = merge(Dict(
        :Date => Dates.Date,
    ), Dict(kw))
    p = r"(.+)\(([^\(\)]+)\)$"
    M = match.(p, names(df))
    n(m::RegexMatch) = m.match => strip(m.captures[1])
    n(m) = nothing
    N = filter(!isnothing, n.(M))
    isempty(N) && return df
    u(m::RegexMatch) = begin
        s = m.captures[2]
        #HACK: assume type constructor if the label starts with `:`
        e = startswith(s, ":") ? Symbol(s[2:end]) : :(@u_str($s))
        #HACK: use Main scope for type constructor evaluation
        #TODO: remove fallback eval in favor of explict constructor mapping
        haskey(D, e) ? D[e] : Main.eval(e)
    end
    u(m) = nothing
    U = u.(M)
    DataFrames.rename(unitfy(df, U), N...)
end
deunitfy(df::DataFrame) = deunitfy(df, repeat([nothing], DataFrames.ncol(df)))

export unitfy, deunitfy
