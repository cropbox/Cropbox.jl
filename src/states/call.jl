import FunctionWrappers: FunctionWrapper
struct Call{V,F<:FunctionWrapper} <: State{V}
    value::F
end

Call(; unit, _value, _type, _calltype, _...) = begin
    V = valuetype(_type, value(unit))
    F = _calltype
    Call{V,F}(_value)
end

#HACK: showing s.value could trigger StackOverflowError
show(io::IO, s::Call) = print(io, "<call>")
