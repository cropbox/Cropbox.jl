struct Gather{T,S,F}
    types::T
    store::S
    callback::F
end

(g::Gather)(a...; k...) = g.callback(a...; k...)

Base.broadcastable(g::Gather) = Ref(g)

Base.push!(g::Gather, v...) = push!(g.store, v...)
Base.append!(g::Gather, v...) = append!(g.store, v...)

value(g::Gather) = g.store
Base.getindex(g::Gather) = value(g)
Base.adjoint(g::Gather) = value(g)

mixindispatch(s, g::Gather) = mixindispatch(s, g.types...)

gather!(s::System, SS::Type{<:System}...; store=[], callback=visit!, kwargs=()) = gather!(Gather(SS, store, callback), s; kwargs...)
gather!(g::Gather, v; kwargs...) = g(g, mixindispatch(v, g)...; kwargs...)

visit!(g::Gather, s::System, ::Val; k...) = (gather!.(g, value.(collect(s)); k...); g')
visit!(g::Gather, V::Vector{<:System}, ::Val; k...) = (gather!.(g, V; k...); g')
visit!(g::Gather, s, ::Val; k...) = g'
visit!(g::Gather, s; k...) = visit!(g, s, Val(nothing); k...)

gathersystem!(g::Gather, s::System, ::Val{:System}) = (push!(g, s); visit!(g, s))
gathersystem!(g::Gather, a...) = visit!(g, a...)

export Gather, gather!, visit!
