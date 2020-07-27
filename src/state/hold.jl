struct Hold{Any} <: State{Any}
    name::Symbol
    alias::Union{Symbol,Nothing}
end

Hold(; _name, _alias, _...) = begin
    Hold{Any}(_name, _alias)
end

constructortags(::Val{:Hold}) = ()

value(s::Hold) = error("cannot read variable on hold: $(s.name) $(isnothing(s.alias) ? "" : "($(s.alias))")")
store!(s::Hold, _) = error("cannot store variable on hold: $(s.name) $(isnothing(s.alias) ? "" : "($(s.alias))")")

genvartype(v::VarInfo, ::Val{:Hold}; _...) = @q Hold{Any}

geninit(v::VarInfo, ::Val{:Hold}) = nothing
