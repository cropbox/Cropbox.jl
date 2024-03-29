abstract type System end

namefor(s::S) where {S<:System} = namefor(S)
namefor(S) = nameof(S)
typefor(s::S) where {S<:System} = S
Base.names(s::S) where {S<:System} = names(S)
Base.names(S::Type{<:System}) = (n = split(String(Symbol(S)), "."); [Symbol(join(n[i:end], ".")) for i in 1:length(n)])

Base.length(s::System) = length(fieldnamesunique(s))
Base.iterate(s::System) = iterate(s, 1)
Base.iterate(s::System, i) = begin
    F = fieldnamesunique(s)
    l = length(F)
    l == 0 ? nothing : (s[F[i]], l == i ? nothing : i+1)
end
Base.iterate(s::System, ::Nothing) = nothing

Base.broadcastable(s::System) = Ref(s)

Base.getindex(s::System, i) = getproperty(s, i)
Base.getindex(s::System, ::Nothing) = s

Base.getproperty(s::System, n::AbstractString) = begin
    isempty(n) && return s
    reduce((a, b) -> begin
        m = match(r"([^\[\]]+)(?:\[(.+)\])?", b)
        n, i = m[1], m[2]
        v = getfield(a, Symbol(n))
        if isnothing(i)
            v
        else
            #HACK: support symbol as-is (i.e. "a[:i]" vs. "a[i]")
            k = if startswith(i, ":")
                i
            elseif isprivatename(i)
                canonicalname(i, n)
            else
                try
                    #HACK: support indexing of non-Variable (i.e. "a[1]" for Vector{Layer})
                    parse(Int, i)
                catch
                    #HACK: support accessing index (i.e. "a[i]")
                    getfield(a, Symbol(i)) |> value
                end
            end
            v[k]
        end
    end, [s, split(n, ".")...])
end

Base.hasproperty(s::System, n::AbstractString) = begin
    try
        getproperty(s, n)
    catch
        return false
    end
    true
end

#HACK: calculate variable body with external arguments for debugging purpose
value(s::S, k::Symbol, a...; kw...) where {S<:System} = begin
    d = dependency(S)
    v = d.M[k]
    P = extractfuncargpair.(v.args)
    kw0 = Dict(k => s[v]' for (k, v) in P)
    kw1 = merge(kw0, kw)
    value(S, k, a...; kw1...)
end
value(S::Type{<:System}, k::Symbol, a...; kw...) = begin
    d = dependency(S)
    v = d.M[k]
    body = v.body
    type = v.type
    emitvars(a) = let p = extractfuncargpair(a), k = p[1]; :($k = $(kw[k])) end
    emitvals(a, v) = let (k, t, u) = extractfunckwargtuple(a); :($k = Cropbox.unitfy($v, $u)) end
    #TODO: check args/kwargs existence
    if v.state in (:Preserve, :Track)
        vars = emitvars.(v.args)
        eval(:($type(let $(vars...); $body end)))
    elseif v.state == :Call
        vars = emitvars.(v.args)
        vals = emitvals.(v.kwargs, a)
        eval(:($type(let $([vars..., vals...]...); $body end)))
    else
        error("unsupported state for value() call form: $v")
    end
end

Base.show(io::IO, s::System) = print(io, "<$(namefor(s))>")
Base.show(io::IO, m::MIME"text/plain", s::System) = look(io, m, s; header=false, doc=false)
Base.show(io::IO, m::MIME"text/html", s::System) = look(io, m, s; header=false, doc=false)

#TODO: see if we can move it to util/look.jl
include("look.jl")

labelstring(v; maxlength=nothing) = begin
    l = repr(v; context=IOContext(devnull, :compact => true, :limit => true))
    n = length(l)
    i = findfirst('\n', l)
    i = isnothing(i) ? n : i-1
    x = isnothing(maxlength) ? n : maxlength
    i = min(i, x)
    i < n ? l[1:i] * "…" : l
end

export System
