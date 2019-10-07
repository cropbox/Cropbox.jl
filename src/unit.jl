using Unitful
import Unitful: Units

unitfy(::Nothing, u) = nothing
unitfy(::Nothing, ::Nothing) = nothing
unitfy(v, ::Nothing) = v
unitfy(v::Number, u::Units) = Quantity(v, u)
unitfy(v::Array, u::Units) = Quantity.(v, u)
unitfy(v::Quantity, u::Units) = uconvert(u, v)
unitfy(v::Array{<:Quantity}, u::Units) = uconvert.(u, v)

# unitstr(s::String) = @eval @u_str $s
# unitstr(s::Unitful.Units) = s
#
# #TODO: make Config type with helper functions
# configstr(s::String) = isletter(s[1]) ? s : unitstr(s)
