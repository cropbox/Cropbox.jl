using Unitful: Unitful, Units, Quantity, @u_str
export @u_str

unitfy(::Nothing, u) = nothing
unitfy(::Nothing, ::Nothing) = nothing
unitfy(::Missing, u) = missing
unitfy(::Missing, ::Nothing) = missing
unitfy(v, ::Nothing) = !hasunit(v) ? deunitfy(v) : error("unable to strip units: $v")
unitfy(::Nothing, ::Missing) = nothing
unitfy(::Missing, ::Missing) = missing
unitfy(v, ::Missing) = v
unitfy(v::Number, u::Units) = Quantity(v, u)
unitfy(v::AbstractArray, u::Units) = unitfy.(v, u)
unitfy(v::Tuple, u::Units) = unitfy.(v, u)
unitfy(v::Quantity, u::Units) = Unitful.uconvert(u, v)
unitfy(v::AbstractArray{<:Union{Quantity,Missing}}, u::Units) = unitfy.(v, u)
unitfy(v::Tuple{Vararg{Union{Quantity,Missing}}}, u::Units) = unitfy.(v, u)
unitfy(v::UnitRange, u::Units) = StepRange(unitfy(v.start, u), unitfy(1, Unitful.absoluteunit(u)), unitfy(v.stop, u))
unitfy(v::StepRange, u::Units) = StepRange(unitfy(v.start, u), unitfy(step(v), Unitful.absoluteunit(u)), unitfy(v.stop, u))
unitfy(v::StepRangeLen, u::Units) = begin
    #HACK: avoid missing zero() for unitfied TwicePrecision called by StepRangeLen constructor
    x = v.ref + step(v)
    E = eltype(x)
    T = typeof(unitfy(E(x), u))
    r = unitfy(E(v.ref), u)
    s = unitfy(step(v), Unitful.absoluteunit(u))
    R = typeof(r)
    S = typeof(s)
    #TODO: use TwicePrecision?
    StepRangeLen{T,R,S}(r, s, length(v), v.offset)
end
unitfy(v, u) = u(v)
unitfy(v::V, ::Type{V}) where V = v

deunitfy(v) = v
deunitfy(v::Quantity) = Unitful.ustrip(v)
deunitfy(v::AbstractArray) = deunitfy.(v)
deunitfy(v::Tuple) = deunitfy.(v)
deunitfy(v::UnitRange) = UnitRange(deunitfy(v.start), deunitfy(v.stop))
deunitfy(v::StepRange) = StepRange(deunitfy(v.start), deunitfy(step(v)), deunitfy(v.stop))
deunitfy(v::StepRangeLen) = StepRangeLen(deunitfy(eltype(v)(v.ref)), deunitfy(step(v)), length(v), v.offset)
deunitfy(v, u) = deunitfy(unitfy(v, u))
deunitfy(v, ::Missing) = deunitfy(v)

promoteunit(u...) = Unitful.promote_unit(filter(!isnothing, u)...)
promoteunit(::Nothing) = nothing
promoteunit() = nothing

hasunit(v::Units) = !Unitful.isunitless(v)
hasunit(::Nothing) = false
hasunit(v) = any(hasunit.(unittype(v)))

using DataFrames: AbstractDataFrame, DataFrame, DataFrames
for f in (:unitfy, :deunitfy)
    @eval $f(df::AbstractDataFrame, U::Vector) = begin
        r = DataFrame()
        for (n, c, u) in zip(propertynames(df), eachcol(df), U)
            r[!, n] = $f.(c, u)
        end
        r
    end
end

import Dates
unitfy(df::AbstractDataFrame; kw...) = begin
    #HACK: default constructor for common types to avoid scope binding issue
    D = merge(Dict(
        :Date => Dates.Date,
    ), Dict(kw))
    p = r"(.+)\(([^\(\)]+)\)$"
    M = match.(p, names(df))
    n(m::RegexMatch) = m.match => strip(m.captures[1])
    n(m) = nothing
    N = filter!(!isnothing, n.(M))
    isempty(N) && return df
    u(m::RegexMatch) = begin
        s = m.captures[2]
        #HACK: assume type constructor if the label starts with `:`
        e = startswith(s, ":") ? Symbol(s[2:end]) : :(@u_str($s))
        #HACK: use Main scope for type constructor evaluation
        #TODO: remove fallback eval in favor of explict constructor mapping
        haskey(D, e) ? D[e] : Main.eval(e)
    end
    u(m) = missing
    U = u.(M)
    DataFrames.rename(unitfy(df, U), N...)
end
unitfy(df::AbstractDataFrame, ::Nothing) = df
deunitfy(df::AbstractDataFrame) = DataFrame(((hasunit(u) ? "$n ($u)" : n) => deunitfy(df[!, n]) for (n, u) in zip(names(df), unittype(df)))...)

export unitfy, deunitfy
