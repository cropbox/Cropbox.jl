using Unitful
import Unitful: DimensionlessUnits, Units

unitfy(v, ::Nothing) = v
unitfy(v, u::Units) = Quantity(v, u)
unitfy(v, u::DimensionlessUnits) = u(v)
unitfy(v::Array, u::Units) = Quantity.(v, u)
unitfy(v::Array, u::DimensionlessUnits) = u.(v)
unitfy(v::Quantity, u::Units) = uconvert(u, v)
unitfy(v::Quantity, u::DimensionlessUnits) = uconvert(u, v)
unitfy(v::Array{<:Quantity}, u::Units) = uconvert.(u, v)
unitfy(v::Array{<:Quantity}, u::DimensionlessUnits) = uconvert.(u, v)

# unitstr(s::String) = @eval @u_str $s
# unitstr(s::Unitful.Units) = s
#
# #TODO: make Config type with helper functions
# configstr(s::String) = isletter(s[1]) ? s : unitstr(s)

macro nounit(args...)
    f(a) = :($(esc(a)) = ustrip($(esc(a))))
    quote $([f.(args)..., nothing]...) end
end

export @nounit
