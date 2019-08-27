using Unitful

unitfy(v, ::Nothing) = v
unitfy(v, u::Unitful.Units) = Quantity(v, u)
unitfy(v, u::Unitful.DimensionlessUnits) = u(v)
unitfy(v::Array, u::Unitful.Units) = Quantity.(v, u)
unitfy(v::Array, u::Unitful.DimensionlessUnits) = u.(v)
unitfy(v::Quantity, u::Unitful.Units) = uconvert(u, v)
unitfy(v::Quantity, u::Unitful.DimensionlessUnits) = uconvert(u, v)
unitfy(v::Array{<:Quantity}, u::Unitful.Units) = uconvert.(u, v)
unitfy(v::Array{<:Quantity}, u::Unitful.DimensionlessUnits) = uconvert.(u, v)

unitstr(s::String) = @eval @u_str $s
unitstr(s::Unitful.Units) = s

#TODO: make Config type with helper functions
configstr(s::String) = isletter(s[1]) ? s : unitstr(s)
