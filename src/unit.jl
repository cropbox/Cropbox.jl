using Unitful

unitfy(v, u::Unitful.Units) = Quantity(v, u)
unitfy(v::Quantity, u::Unitful.Units) = uconvert(u, v)

unitstr(s::String) = @eval @u_str $s
unitstr(s::Unitful.Units) = s

#TODO: make Config type with helper functions
configstr(s::String) = isletter(s[1]) ? s : unitstr(s)
