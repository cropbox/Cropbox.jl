mutable struct Flag{Bool} <: State{Bool}
    value::Bool
end

Flag(; _value, _...) = begin
    Flag{Bool}(_value)
end
