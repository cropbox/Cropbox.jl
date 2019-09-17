using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S<:Union{Symbol,Nothing}}
    name::Symbol
    alias::Vector{Symbol}
    args::Vector
    kwargs::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::S
    type::Union{Symbol,Expr,Nothing}
    tags::Dict{Symbol,Any}
    line::Union{Expr,Symbol}
end

import Base: show
show(io::IO, i::VarInfo) = begin
    println(io, "name: $(i.name)")
    println(io, "alias: $(i.alias)")
    println(io, "func ($(repr(i.args)); $(repr(i.kwargs))) = $(repr(i.body))")
    println(io, "state: $(repr(i.state))")
    println(io, "type: $(repr(i.type))")
    for (k, v) in i.tags
        println(io, "tag $k = $(repr(v))")
    end
    println(io, "line: $(i.line)")
end

VarInfo(line::Union{Expr,Symbol}) = begin
    # name[(args..; kwargs..)][: alias | [alias...]] [=> body] ~ [state][::type][(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, state_::type_(tags__) | ::type_(tags__) | state_(tags__) | state_::type_ | ::type_ | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: [alias__]) | (def2_: alias__) | def2_)
    @capture(def2, name_(args__; kwargs__) | name_(; kwargs__) | name_(args__) | name_)
    args = isnothing(args) ? [] : args
    kwargs = isnothing(kwargs) ? [] : kwargs
    alias = isnothing(alias) ? [] : alias
    state = isnothing(state) ? nothing : Symbol(uppercasefirst(string(state)))
    type = @capture(type, [elemtype_]) ? :(Vector{$elemtype}) : type
    tags = parsetags(tags, type, state, args, kwargs)
    VarInfo{typeof(state)}(name, alias, args, kwargs, body, state, type, tags, line)
end

parsetags(::Nothing, a...) = parsetags([], a...)
parsetags(tags::Vector, type, state, args, kwargs) = begin
    d = Dict{Symbol,Any}()
    for t in tags
        if @capture(t, k_=v_)
            if @capture(k, kn_::kt_)
                d[kn] = v
                d[Symbol("_type_", kn)] = kt
            else
                d[k] = v
            end
        elseif @capture(t, @u_str(v_))
            d[:unit] = :@u_str($v)
        else
            d[t] = true
        end
    end
    !haskey(d, :unit) && (d[:unit] = nothing)
    if state == :Call
        #FIXME: lower duplicate efforts in vartype()
        N = isnothing(type) ? :Float64 : esc(type)
        U = get(d, :unit, nothing)
        V = @q $C.valuetype($N, $U)
        extract(a) = let k, t, u
            @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
            t = isnothing(t) ? :Float64 : esc(t)
            @q $C.valuetype($t, $u)
        end
        F = @q FunctionWrapper{$V, Tuple{$(extract.(kwargs)...)}}
        d[:_calltype] = F
    end
    (state in (:Accumulate, :Capture)) && !haskey(d, :time) && (d[:time] = :(context.clock.tick))
    !isnothing(type) && (d[:_type] = esc(type))
    d
end

names(i::VarInfo) = [i.name, i.alias...]

####

abstract type Step end
struct PreStep <: Step end
struct MainStep <: Step end
struct PostStep <: Step end

suffix(::PreStep) = "_pre"
suffix(::MainStep) = "_main"
suffix(::PostStep) = "_post"

struct VarNode
    info::VarInfo
    step::Step #TODO: rename to VarStep?
end

prev(n::VarNode) = begin
    if n.step == MainStep()
        VarNode(n.info, PreStep())
    elseif n.step == PostStep()
        VarNode(n.info, MainStep())
    elseif n.step == PreStep()
        error("Pre-step node can't have a previous node: $n")
    end
end

####

const C = :($(esc(:Cropbox)))

# posedparams(infos) = begin
#     K = union(Set.(vartype.(infos))...) |> collect
#     V = [Symbol(string(hash(k); base=62)) for k in K]
#     Dict(zip(K, V))
# end
# genvartype(i::VarInfo, params) = begin
#     P = vartype(i)
#     if isnothing(i.state)
#         @assert length(P) == 1
#         :($(esc(params[P[1]])))
#     else
#         :($C.$(i.state){$([:($(esc(params[p]))) for p in P]...)})
#     end
# end
#
# vartype(i::VarInfo{Nothing}) = (i.name,) # ()
# vartype(i::VarInfo{Symbol}) = vartype(i, Val(i.state))
# vartype(i::VarInfo, ::Val{:Hold}) = (Any,)
# vartype(i::VarInfo, ::Val{:Advance}) = ((isnothing(i.type) ? Int64 : i.type, get(i.tags, :unit, nothing)),)
# vartype(i::VarInfo, ::Val{:Preserve}) = ((isnothing(i.type) ? i.name : i.type, get(i.tags, :unit, nothing)),)
# vartype(i::VarInfo, ::Union{Val{:Track},Val{:Drive}}) = ((isnothing(i.type) ? Float64 : i.type, get(i.tags, :unit, nothing)),)
# vartype(i::VarInfo, ::Val{:Call}) = begin
#     V = (isnothing(i.type) ? Float64 : i.type, get(i.tags, :unit, nothing))
#     F = i.name
#     (V, F)
# end
# vartype(i::VarInfo, ::Union{Val{:Accumulate},Val{:Capture}}) = begin
#     V = (isnothing(i.type) ? Float64 : i.type, get(i.tags, :unit, nothing))
#     T = get(i.tags, :time, nothing)
#     R = (V, T)
#     (V, T, R)
# end
# vartype(i::VarInfo, ::Val{:Flag}) = (Bool,)
# vartype(i::VarInfo, ::Val{:Produce}) = (:System,)
# vartype(i::VarInfo, ::Val{:Solve}) = ((isnothing(i.type) ? Float64 : i.type, get(i.tags, :unit, nothing)),)

genvartype(i::VarInfo) = vartype(i)

vartype(i::VarInfo{Nothing}) = esc(i.type)
vartype(i::VarInfo{Symbol}) = begin
    N = isnothing(i.type) ? :Float64 : esc(i.type)
    U = get(i.tags, :unit, nothing)
    V = @q $C.valuetype($N, $U)
    vartype(i, Val(i.state); N=N, U=U, V=V)
end
vartype(i::VarInfo, ::Val{:Hold}; _...) = @q Hold{Any}
vartype(i::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}
vartype(i::VarInfo, ::Val{:Preserve}; V, _...) = @q Preserve{$V}
vartype(i::VarInfo, ::Val{:Track}; V, _...) = @q Track{$V}
vartype(i::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}
vartype(i::VarInfo, ::Val{:Call}; V, _...) = begin
    #F = @q typeof($(symcall(i)))
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        t = isnothing(t) ? :Float64 : esc(t)
        @q $C.valuetype($t, $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(i.kwargs)...)}}
    @q Call{$V,$F}
end
vartype(i::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    #TODO: automatic inference without explicit `timeunit` tag
    TU = get(i.tags, :timeunit, nothing)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end
vartype(i::VarInfo, ::Val{:Capture}; N, U, V, _...) = begin
    TU = get(i.tags, :timeunit, nothing)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Capture{$V,$T,$R}
end
vartype(i::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}
vartype(i::VarInfo, ::Val{:Produce}; _...) = begin
    S = isnothing(i.type) ? :System : esc(i.type)
    @q Produce{$S}
end
vartype(i::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

posedbaseparams(infos) = begin
    d = Dict{Symbol,Any}()
    for i in infos
        if isnothing(i.state)
            P = vartype(i)
            p = P[1]
            k = Symbol(string(hash(p); base=62))
            v = varbasetype(i)
            !isnothing(v) && (d[k] = v)
        end
    end
    d
end
varbasetype(i::VarInfo{Nothing}) = i.type
varbasetype(i::VarInfo{Symbol}) = nothing

genheadertype(t, baseparams) = begin
    b = get(baseparams, t, nothing)
    if isnothing(b)
        :($(esc(t)))
    else
        :($(esc(t)) <: $(esc(b)))
    end
end

posedvars(infos) = names.(infos) |> Iterators.flatten |> collect

gencall(i::VarInfo) = gencall(i, Val(i.state))
gencall(i::VarInfo, ::Val) = nothing
gencall(i::VarInfo, ::Val{:Call}) = begin
    # key(a) = let k, v; @capture(a, k_=v_) ? k : a end
    # emit(a) = @q $(esc(key(a)))
    # args = Tuple(emit.(i.args)) #Tuple(:(esc(a)) for a in i.args)
    # @q function $(symcall(i))($(args...); $(Tuple(i.kwargs)...)) $(i.body) end
    args = genfuncargs(i)
    body = flatten(@q let $args; $(i.body) end)
    @q function $(symcall(i))($(Tuple(i.kwargs)...)) $body end
end
gencalls(infos) = filter(!isnothing, gencall.(infos))

# genfield(i::VarInfo, params) = genfield(genvartype(i, params), i.name, i.alias)
# genfield(type, name, alias) = @q begin
#     $name::$type
#     $(@q begin $([:($a::$type) for a in alias]...) end)
# end
genfield(type, name, alias) = @q begin
    $name::$type
    $(@q begin $([:($a::$type) for a in alias]...) end)
end
# genfields(infos, params) = [genfield(i, params) for i in infos]
genfield(i::VarInfo) = genfield(genvartype(i), i.name, i.alias)
genfields(infos) = [genfield(i) for i in infos]

genparamdecl(i::VarInfo, params) = begin
    P = vartype(i)
    if isnothing(i.state)
        @q $(esc(params[P[1]])) = typeof($(i.name))
    else
        @q ($([esc(params[p]) for p in P]...),) = typeof($(i.name)).parameters
    end
end
genparamdecls(infos, params) = [genparamdecl(i, params) for i in infos]

equation(f; static=false) = begin
    fdef = splitdef(f)
    name = Meta.quot(fdef[:name])
    key(x::Symbol) = x
    key(x::Expr) = x.args[1]
    args = key.(fdef[:args]) |> Tuple{Vararg{Symbol}}
    kwargs = key.(fdef[:kwargs]) |> Tuple{Vararg{Symbol}}
    pair(x::Symbol) = nothing
    pair(x::Expr) = x.args[1] => x.args[2]
    default = filter(!isnothing, [pair.(fdef[:args]); pair.(fdef[:kwargs])]) |> Vector{Pair{Symbol,Any}}
    # ensure default values are evaled (i.e. `nothing` instead of `:nothing`)
    default = :(Dict{Symbol,Any}(k => $(esc(:eval))(v) for (k, v) in $default))
    body = Meta.quot(fdef[:body])
    func = @q function $(esc(gensym(fdef[:name])))($(esc.(fdef[:args])...); $(esc.(fdef[:kwargs])...)) $(esc(fdef[:body])) end
    :($C.Equation($func, $name, $args, $kwargs, $default, $body; static=$static))
end

macro equation(f)
    e = equation(f)
    #FIXME: redundant call of splitdef() in equation()
    name = splitdef(f)[:name]
    :($(esc(name)) = $e)
end

genoverride(name, default) = @q get(_kwargs, $(Meta.quot(name)), $default)

import DataStructures: OrderedSet
gendecl(N::Vector{VarNode}) = gendecl.(OrderedSet([n.info for n in N]))
gendecl(i::VarInfo{Symbol}) = begin
    static = get(i.tags, :static, false)
    if isnothing(i.body)
        if isempty(i.args)
            # use externally defined equation
            e = esc(i.name)
        elseif length(i.args) == 1
            # shorthand syntax for single value arg without key
            a = i.args[1]
            if @capture(a, k_=v_)
                # `f(a="b") ~ ...` expands to `f(a="b") => a ~ ...`
                f = @q function $(i.name)($k=$v) $k end
            elseif typeof(a) <: Symbol
                # `f(a) ~ ...` expands to `f(a) => a ~ ...`
                f = @q function $(i.name)($a) $a end
            else
                # `f("a") ~ ...` expands to `f(x="a") => x ~ ...`
                f = @q function $(i.name)(x=$a) x end
            end
            e = equation(f; static=static)
        else
            @error "Function not provided: $(i.name)"
        end
    else
        f = @q function $(i.name)($(Tuple(i.args)...)) $(i.body) end
        e = equation(f; static=static)
    end
    name = Meta.quot(i.name)
    alias = Tuple(i.alias)
    value = get(i.tags, :override, false) ? genoverride(i.name, geninit(i)) : geninit(i)
    stargs = [:($(esc(k))=$v) for (k, v) in i.tags]
    decl = :($C.$(i.state)(; _name=$name, _alias=$alias, _value=$value, $(stargs...)))
    gendecl(decl, i.name, i.alias)
end
gendecl(i::VarInfo{Nothing}) = begin
    #@assert isempty(i.args) "Non-Var `$(i.name)` cannot have arguments: $(i.args)"
    if get(i.tags, :override, false)
        decl = genoverride(i.name, esc(i.body))
    elseif !isnothing(i.body)
        decl = esc(i.body)
    else
        decl = :($(esc(i.type))())
    end
    # implicit :expose
    decl = :($(esc(i.name)) = $decl)
    gendecl(decl, i.name, i.alias)
end
gendecl(decl, var, alias) = @q begin
    $(LineNumberNode(0, "gendecl/$var"))
    $var = $decl
    $(@q begin $([:($a = $var) for a in alias]...) end)
end

gensource(infos) = begin
    l = [i.line for i in infos]
    striplines(flatten(@q begin $(l...) end))
end

genfieldnamesunique(infos) = Tuple(i.name for i in infos)

genstruct(name, infos, incl) = begin
    S = esc(name)
    nodes = sortednodes(name, infos)
    #params = posedparams(infos)
    #types = [:($(esc(t))) for t in values(params)]
    #baseparams = posedbaseparams(infos)
    #headertypes = [genheadertype(t, baseparams) for t in values(params)]
    #fields = genfields(infos, params)
    calls = gencalls(infos)
    fields = genfields(infos)
    decls = gendecl(nodes)
    #paramdecls = genparamdecls(infos, params)
    vars = posedvars(infos)
    source = gensource(infos)
    system = @q begin
        #$(calls...)
        #struct $name{$(headertypes...)} <: $C.System
        struct $name <: $C.System
            $(fields...)
            function $name(; _kwargs...)
                _names = $C.names.([$C.mixins($name)..., $name]) |> Iterators.flatten |> collect
                $(decls...)
                #$(paramdecls...)
                #new{$(types...)}($(vars...))
                new($(vars...))
            end
        end
        $C.source(::Val{$(Meta.quot(name))}) = $(Meta.quot(source))
        $C.mixins(::Type{<:$S}) = Tuple($(esc(:eval)).($incl))
        $C.fieldnamesunique(::Type{<:$S}) = $(genfieldnamesunique(infos))
        #HACK: redefine them to avoid world age problem
        @generated $C.collectible(::Type{<:$S}) = $C.filteredfields(Union{$C.System, Vector{$C.System}, $C.Produce{<:Any}}, $S)
        @generated $C.updatable(::Type{<:$S}) = $C.filteredvars($S)
        # $C.collectible(::Type{<:$S}) = $(gencollectible(infos))
        # $C.updatable(::Type{<:$S}) = $(genupdatable(infos))
        $C.updatestatic!($(esc(:self))::$S) = $(genupdate(nodes))
        $S
    end
    flatten(system)
end

#TODO: maybe need to prevent naming clash by assigning UUID for each System
source(s::S) where {S<:System} = source(S)
source(S::Type{<:System}) = source(nameof(S))
source(s::Symbol) = source(Val(s))
source(::Val{:System}) = @q begin
    context ~ ::Cropbox.Context(override)
    config(context) => context.config ~ ::Cropbox.Config
end
mixins(::Type{<:System}) = [System]
mixins(s::S) where {S<:System} = mixins(S)

# gencollectible(infos) = begin
#     I = filter(i -> i.type in (:(Cropbox.System), :System, :(Vector{Cropbox.System}), :(Vector{System}), :(Cropbox.Produce), :Produce), infos)
#     filter!(i -> !get(i.tags, :override, false), I)
#     map(i -> i.name, I) |> Tuple
# end
# genupdatable(infos) = begin
#     I = filter(i -> isnothing(i.type), infos)
#     map(i -> i.name, I) |> Tuple
# end

fieldnamesunique(::Type{<:System}) = ()
filtervar(type::Type, ::Type{S}) where {S<:System} = begin
    l = collect(zip(fieldnames(S), fieldtypes(S)))
    F = fieldnamesunique(S)
    filter!(p -> p[1] in F, l)
    filter!(p -> p[2] <: type, l)
end
filteredfields(type::Type, ::Type{S}) where {S<:System} = begin
    l = filtervar(type, S)
    map(p -> p[1], l) |> Tuple{Vararg{Symbol}}
end
filteredvars(::Type{S}) where {S<:System} = begin
    l = filtervar(State, S)
    d = Symbol[]
    for (n, T) in l
        push!(d, n)
    end
    Tuple(d)
end
#@generated collectible(::Type{S}) where {S<:System} = filteredfields(Union{System, Vector{System}, Var{<:Produce}}, S)
#@generated updatable(::Type{S}) where {S<:System} = filteredvars(S)
@generated updatestatic!(::System) = nothing

parsehead(head) = begin
    @capture(head, name_(mixins__) | name_)
    mixins = isnothing(mixins) ? [] : mixins
    incl = [:System]
    for m in mixins
        push!(incl, m)
    end
    (name, incl)
end

import DataStructures: OrderedDict, OrderedSet
gensystem(head, body) = gensystem(parsehead(head)..., body)
gensystem(name, incl, body) = genstruct(name, geninfos(body, incl), incl)
geninfos(body, incl) = begin
    con(b) = OrderedDict(i.name => i for i in VarInfo.(striplines(b).args))
    add!(d, b) = begin
        for (n, i) in con(b)
            (i.state == :Hold) && haskey(d, n) && continue
            d[n] = i
        end
    end
    d = OrderedDict{Symbol,VarInfo}()
    for m in incl
        add!(d, source(m))
    end
    add!(d, body)
    collect(values(d))
end

include("dependency.jl")
sortednodes(name, infos) = begin
    M = Dict{Symbol,VarInfo}()
    for v in infos
        for n in names(v)
            M[n] = v
        end
    end
    d = Dependency(M)
    add!(d, infos)
    #HACK: for debugging
    save(d, name)
    sort(d)
end

macro system(head, body)
    gensystem(head, body)
end

macro infos(head, body)
    geninfos(body, parsehead(head)[2])
end

export @equation, @system

####

#=
# _predator_population_var / pre
predator_population = _predator_population_state.value
P = predator_population

# _predator_reproduction_rate_var / main
#v# = let
    0.75
end
predator_reproductaion_rate = let s=_predator_reproduction_rate_var.state
    store!(_predator_reproduction_rate_state, #v#)
    s.value
end
d = predator_reproduction_rate

# _timestep_var / main
#v# = let t=resolve(s, "context.clock.tick")
    0.01t
end
timestep = let s=_timestep_var.state
    store!(s, #v#) # track
    s.value
end
t = timestep

# _predator_population_var / main
predator_population = let s=_predator_population_state
    t = value(s.time.tick)
    t0 = s.tick
    if ismissing(t0)
        v = value(s.init)
    else
        v = s.value + s.rate * (t - t0)
    end
    store!(s, v)
    s.value
end

# _predator_population_var / post
#v# = let
  d*b*H*P - c*P
end
let s=_predator_population_state
    t = value(s.time.tick)
    r = unitfy(#v#, rateunit(s))
    f = () -> (s.tick = t; s.rate = r)
    p = priority(s)
    i = o.order #FIXME: should no longer be needed?
    queue!(order, f, p, i)
end

=#

geninit(v::VarInfo) = geninit(v, Val(v.state))
geninit(v::VarInfo, ::Val) = @q $C.unitfy($(genfunc(v)), $C.value($(v.tags[:unit])))
geninit(v::VarInfo, ::Val{:Hold}) = nothing
geninit(v::VarInfo, ::Val{:Advance}) = missing
geninit(v::VarInfo, ::Val{:Preserve}) = begin
    i = @q $C.unitfy($(genfunc(v)), $C.value($(v.tags[:unit])))
    if get(v.tags, :parameter, false)
        @gensym o
        @q let $o = $C.option(config, _names, $(names(v)))
            isnothing($o) ? $i : $o
        end
    else
        i
    end
end
geninit(v::VarInfo, ::Val{:Drive}) = begin
    k = get(v.tags, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @q $C.unitfy($C.value($(genfunc(v))[$k]), $C.value($(v.tags[:unit])))
end
geninit(v::VarInfo, ::Val{:Call}) = begin
    #symcall(v)

    pair(a) = let k, v; @capture(a, k_=v_) ? k => v : a => a end
    emiti(a) = (p = pair(a); @q $(esc(p[1])) = $C.value($(p[2])))
    innerargs = @q begin $(emiti.(v.args)...) end

    innercall = flatten(@q let $innerargs; $(esc(v.body)) end)
    innerbody = @q $C.unitfy($innercall, $C.value($(v.tags[:unit])))

    emito(a) = (p = pair(a); @q $(esc(p[1])) = $(p[2]))
    outerargs = @q begin $(emito.(v.args)...) end

    extract(a) = let k, t, u; @capture(a, k_::t_(u_) | k_::t_ | k_(u_)) ? k : a end
    emitc(a) = @q $(esc(extract(a)))
    callargs = Tuple(emitc.(v.kwargs))

    @q function $(symcall(v))($(callargs...))
        $innerbody
    end
    # outerbody = flatten(@q let $outerargs
    #     function $(symcall(v))($(callargs...))
    #         $innerbody
    #     end
    # end)
    #
    # key(a) = let k, v; @capture(a, k_=v_) ? k : a end
    # emitf(a) = @q $(esc(key(a)))
    # fillargs = Tuple(emitf.(v.args))
    #
    # @q function $(symcall(v))($(fillargs...); $(callargs...)) $outerbody end
end
geninit(v::VarInfo, ::Val{:Accumulate}) = @q $C.unitfy($C.value($(get(v.tags, :init, nothing))), $C.value($(v.tags[:unit])))
geninit(v::VarInfo, ::Val{:Capture}) = nothing
geninit(v::VarInfo, ::Val{:Flag}) = false
geninit(v::VarInfo, ::Val{:Produce}) = nothing
geninit(v::VarInfo, ::Val{:Solve}) = nothing
geninit(v::VarInfo, ::Val{:Resolve}) = @q $C.unitfy($C.value($(get(v.tags, :init, nothing))), $C.value($(v.tags[:unit])))

####

genupdate(nodes) = begin
    @q begin
        $([genupdateinit(n) for n in nodes]...)
        $([genupdate(n) for n in nodes]...)
        nothing
    end
end

symstate(v::VarInfo) = Symbol(:_state_, v.name)
symlabel(v::VarInfo, t::Step, s...) = Symbol(v.name, suffix(t), s...)
symcall(v::VarInfo) = Symbol(v.name, :_call)

genupdateinit(n::VarNode) = begin
    v = n.info
    s = symstate(v)
    if isnothing(v.state)
        # implicit :expose
        @q begin
            $s = $(v.name) = self.$(v.name)
            $([:($a = $s) for a in v.alias]...)
        end
    else
        @q $s = self.$(v.name)
    end
end

genupdate(n::VarNode) = genupdate(n.info, n.step)
genupdate(v::VarInfo, t::Step) = begin
    u = genupdate(v, Val(v.state), t)
    l = symlabel(v, t)
    if isnothing(u)
        @q @label $l
    else
        @q begin
            $(LineNumberNode(0, "genupdate/$(v.name)"))
            @label $l
            $(v.name) = $u
            $([:($a = $(v.name)) for a in v.alias]...)
        end
    end
end
genupdate(v::VarInfo, t::PostStep) = @q begin
    @label $(symlabel(v, t))
    $C.queue!(context.queue, $(genupdate(v, Val(v.state), t)), $C.priority($C.$(v.state)))
end

genvalue(v::VarInfo) = :($C.value($(symstate(v))))
genstore(v::VarInfo) = begin
    @gensym s f
    @q let $s = $(symstate(v)),
           $f = $(genfunc(v))
        $C.store!($s, $f)
        #TODO: make store! return value
        $C.value($s)
    end
end

genupdate(v::VarInfo, ::Val{nothing}, ::MainStep) = nothing

genupdate(v::VarInfo, ::Val, ::PreStep) = genvalue(v)
genupdate(v::VarInfo, ::Val, ::MainStep) = genstore(v)
genupdate(v::VarInfo, ::Val, ::PostStep) = nothing

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.advance!($s)
    end
end

genupdate(v::VarInfo, ::Val{:Preserve}, ::MainStep) = genvalue(v)

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep) = begin
    k = get(v.tags, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @gensym s f d
    @q let $s = $(symstate(v)),
           $f = $(genfunc(v)),
           $d = $C.value($f[$k])
        $C.store!($s, $d)
        #TODO: make store! return value
        $C.value($s)::$C.valuetype($s)
    end # value() for Var
end

genupdate(v::VarInfo, ::Val{:Call}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.value($s)
    end
end
# begin
#     key(a) = let k, v; @capture(a, k_=v_) ? k : a end
#     args = [key(a) for a in v.args]
#     @show args
#     @q let s = $(symstate(v)),
#            k = $(gensym(:k))
#         #FIXME: need to patch function arguments here
#         #s.value = (a...; k...) -> $C.unitfy(f()(a...; k...), $C.unit(s))
#         #(; k...) -> $C.unitfy(f()(a...; k...), $C.unit(s))
#         (; k...) -> function ($(args...); k...)
#             $C.unitfy($(genfunc(v)), $C.unit(s))
#         end
#     end
# end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::MainStep) = begin
    @gensym s t t0 a
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $t0 = $s.tick,
           $a = $s.value + $s.rate * ($t - $t0)
        $C.store!($s, $a)
        #TODO: make store! return value
        $C.value($s)
    end
end
genupdate(v::VarInfo, ::Val{:Accumulate}, ::PostStep) = begin
    @gensym s t f r
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s))
        () -> ($s.tick = $t; $s.rate = $r)
    end
end

genupdate(v::VarInfo, ::Val{:Capture}, ::MainStep) = begin
    @gensym s t t0 d
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $t0 = $s.tick,
           $d = $s.rate * ($t - $t0)
        $C.store!($s, $d)
        #TODO: make store! return value
        $C.value($s)
    end
end
genupdate(v::VarInfo, ::Val{:Capture}, ::PostStep) = begin
    @gensym s t f r
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s))
        () -> ($s.tick = $t; $s.rate = $r)
    end
end

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = genvalue(v)
genupdate(v::VarInfo, ::Val{:Flag}, ::PostStep) = begin
    @gensym s f
    #FIXME: make type stable oneway
    if get(v.tags, :oneway, false)
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v))
            !$C.value($s) ? () -> $C.store!($s, $f) : nothing
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v))
            () -> $C.store!($s, $f)
        end
    end
end

genupdate(v::VarInfo, ::Val{:Produce}, ::MainStep) = symstate(v)
genupdate(v::VarInfo, ::Val{:Produce}, ::PostStep) = begin
    @gensym s P c o
    @q let $s = $(symstate(v)),
           $P = $(genfunc(v)),
           $c = context,
           $o = context.order
        if !(isnothing($P) || isempty($P))
            function ()
                for p in $P
                    append!($s.value, p.type(; context=$c, p.args...))
                end
                $C.inform!($o)
            end
        end
    end
end

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    N_MAX = 100
    TOL = 0.0001
    lstart = symlabel(v, PreStep())
    lexit = symlabel(v, MainStep(), :_exit)
    @gensym s d zero tol
    @q let $s = $(symstate(v)),
           $zero = $C.unitfy(0, $C.unit($s))
           $tol = $C.unitfy($TOL, $C.unit($s))
        if $s.step == :z
            $s.N = 0
            $s.a = $C.value($s.lower)
            $s.b = $C.value($s.upper)
            $s.step = :a
            $C.store!($s, $s.a)
            @goto $lstart
        elseif $s.step == :a
            $s.fa = $C.value($s) - $(genfunc(v))
            #@show "solve: $($s.a) => $($s.fa)"
            $s.step = :b
            $C.store!($s, $s.b)
            @goto $lstart
        elseif $s.step == :b
            $s.fb = $C.value($s) - $(genfunc(v))
            #@show "solve: $($s.b) => $($s.fb)"
            @assert sign($s.fa) != sign($s.fb)
            $s.N = 1
            $s.c = ($s.a + $s.b) / 2
            $C.store!($s, $s.c)
            $s.step = :c
            @goto $lstart
        elseif $s.step == :c
            $s.fc = $C.value($s) - $(genfunc(v))
            #@show "solve: $($s.c) => $($s.fc)"
            if $s.fc ≈ $zero || ($s.b - $s.a) < $tol
                $s.step = :z
                #@show "solve: finished! $($C.value($s))"
                @goto $lexit
            else
                $s.N += 1
                if $s.N > $N_MAX
                    @show #= @error =# "solve: convergence failed!"
                    $s.step = :z
                    @goto $lexit
                end
                if sign($s.fc) == sign($s.fa)
                    $s.a = $s.c
                    $s.fa = $s.fc
                    #@show "solve: a <- $($s.c)"
                else
                    $s.b = $s.c
                    $s.fb = $s.fc
                    #@show "solve: b <- $($s.c)"
                end
                $s.c = ($s.a + $s.b) / 2
                $C.store!($s, $s.c)
                @goto $lstart
            end
        end
        @label $lexit
        $C.value($s)
    end
end

#TODO: reimplement Solve
# update!(s::Solve, f::AbstractVar, ::MainStep) = begin
#     #@show "begin solve $s"
#     trigger(x) = (store!(s, x); recite!(s.context.order, f))
#     cost(e) = x -> (trigger(x); e(x) |> ustrip)
#     b = (value(s.lower), value(s.upper))
#     if nothing in b
#         try
#             c = cost(x -> (x - f())^2)
#             v = find_zero(c, value(s))
#         catch e
#             #@show "convergence failed: $e"
#             v = value(s)
#         end
#     else
#         c = cost(x -> (x - f()))
#         v = find_zero(c, b, Roots.AlefeldPotraShi())
#     end
#     #HACK: trigger update with final value
#     trigger(v)
#     recitend!(s.context.order, f)
# end

genfuncargs(v::VarInfo) = begin
    pair(a) = let k, v; @capture(a, k_=v_) ? k => v : a => a end
    emit(a) = begin
        p = pair(a)
        @q $(esc(p[1])) = $C.value($(p[2]))
    end
    @q begin $(emit.(v.args)...) end
end
genfunc(v::VarInfo) = begin
    args = genfuncargs(v)
    body = if isnothing(v.body) && length(v.args) == 1
        # shorthand syntax for single value arg without key
        a = v.args[1]
        @capture(a, k_=_) ? :($k) : :($a)
    else
        v.body
    end
    body = esc(body)
    flatten(@q let $args; $body end)
end
