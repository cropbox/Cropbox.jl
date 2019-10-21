using Interpolations
import Interpolations: Extrapolation
import DataStructures: OrderedDict

struct Interpolate{V} <: State{V}
    #TODO: check performance of non-concrete type
    value::Extrapolation{V}
end

Interpolate(; unit, knotunit, reverse, _value, _type, _...) = begin
    l = if typeof(_value) <: Extrapolation
        i = _value.itp
        if reverse
            #HACK: reverse interpolation
            zip(i.coefs, i.knots[1])
        else
            zip(i.knots[1], i.coefs)
        end
    else
        if typeof(_value) <: Matrix
            zip(_value[:, 1], _value[:, 2])
        else
            _value
        end
    end
    d = OrderedDict(l)
    sort!(d)
    K = unitfy(collect(keys(d)), value(knotunit))
    V = unitfy(collect(values(d)), value(unit))
    v = LinearInterpolation(K, V)
    #HACK: pick up unitfy-ed valuetype
    V = typeof(v).parameters[1]
    Interpolate{V}(v)
end
