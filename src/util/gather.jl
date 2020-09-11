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
Base.adjoint(g::Gather) = value(g)

mixindispatch(s, g::Gather) = mixindispatch(s, g.types...)

gather!(s::System, SS::Type{<:System}...; store=[], callback=visit!) = gather!(Gather(SS, store, callback), s)
gather!(g::Gather, v) = g(g, mixindispatch(v, g)...)

visit!(g::Gather, s::System, ::Val) = (gather!.(g, value.(collect(s))); g')
visit!(g::Gather, V::Vector{<:System}, ::Val) = (gather!.(g, V); g')
visit!(g::Gather, s, ::Val) = g'
visit!(g::Gather, s) = visit!(g, s, Val(nothing))

gathersystem!(g::Gather, s::System, ::Val{:System}) = (push!(g, s); visit!(g, s))
gathersystem!(g::Gather, a...) = visit!(g, a...)

export Gather, gather!, visit!
