struct Hold{Any} <: State{Any}
end

Hold(; _...) = begin
    Hold{Any}()
end

genvartype(v::VarInfo, ::Val{:Hold}; _...) = @q Hold{Any}

geninit(v::VarInfo, ::Val{:Hold}) = nothing
