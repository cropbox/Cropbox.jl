struct Hold{Any} <: State{Any}
end

Hold(; _...) = begin
    Hold{Any}()
end
