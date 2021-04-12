using MacroTools: MacroTools, isexpr, isline, @capture, @q
using Setfield: @set

struct VarInfo{S<:Union{Symbol,Nothing}}
    system::Symbol
    name::Symbol
    alias::Union{Symbol,Nothing}
    args::Vector
    kwargs::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::S
    type::Union{Symbol,Expr,Nothing}
    tags::Dict{Symbol,Any}
    line::Expr
    linenumber::LineNumberNode
    docstring::String
end

Base.show(io::IO, v::VarInfo) = begin
    println(io, "system: $(v.system)")
    println(io, "name: $(v.name)")
    println(io, "alias: $(v.alias)")
    println(io, "func ($(repr(v.args)); $(repr(v.kwargs))) = $(repr(v.body))")
    println(io, "state: $(repr(v.state))")
    println(io, "type: $(repr(v.type))")
    for (a, b) in v.tags
        println(io, "tag $a = $(repr(b))")
    end
    println(io, "line: $(v.line)")
    println(io, "linenumber: $(v.linenumber)")
    println(io, "docstring: $(v.docstring)")
end

VarInfo(system::Symbol, line::Expr, linenumber::LineNumberNode, docstring::String, scope::Module, substs::Dict) = begin
    # name[(args..; kwargs..)][: alias] [=> body] [~ [state][::stype|<:dtype][(tags..)]]
    @capture(bindscope(line, scope), (decl_ ~ deco_) | decl_)
    @capture(deco,
        (state_::stype_(tags__)) | (::stype_(tags__)) | (state_::stype_) | (::stype_) |
        (state_<:dtype_(tags__)) | (<:dtype_(tags__)) | (state_<:dtype_) | (<:dtype_) |
        state_(tags__) | state_
    )
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: alias_) | def2_)
    @capture(def2, name_(args__; kwargs__) | name_(; kwargs__) | name_(args__) | name_)
    name = parsename(name, system)
    args = parseargs(args, system)
    kwargs = parsekwargs(kwargs)
    body = parsebody(body)
    state = parsestate(state)
    type = parsetype(stype, dtype, state, scope, substs)
    tags = parsetags(tags; name, alias, args, kwargs, state, type)
    try
        VarInfo{typeof(state)}(system, name, alias, args, kwargs, body, state, type, tags, line, linenumber, docstring)
    catch
        error("unrecognized variable declaration: $line")
    end
end

#HACK: experimental support for scope placeholder `:$`
bindscope(l, s::Module) =  MacroTools.postwalk(x -> @capture(x, :$) ? nameof(s) : x, l)

parsename(name, system) = canonicalname(name, system)
canonicalname(n::Symbol, s::Symbol) = isprivatename(n) ? Symbol("__$(s)_$(n)") : n
canonicalname(n, _) = n
splitcanonicalname(n::Symbol) = begin
    m = match(r"__(.+)__(.+)", string(n))
    isnothing(m) ? (nothing, n) : Symbol.((m[1], '_' * m[2]))
end
isprivatename(n) = begin
    s = string(n)
    #HACK: support private variable name with single prefix `_` (i.e. _a => __S__a, __b => __b)
    startswith(s, "_") && !startswith(s, "__")
end
privatename(n::Symbol) = isprivatename(n) ? Symbol(string(n)[2:end]) : n

#TODO: prefixscope to args/kwargs type specifier?
parseargs(args, system) = parsearg.(args, system)
#HACK: support private variable name in the dependency list
parsearg(a::Symbol, system) = Expr(:kw, privatename(a), canonicalname(a, system))
parsearg(a::Expr, system) = @capture(a, k_=v_) ? Expr(:kw, k, canonicalname(v, system)) : a
parseargs(::Nothing, _) = []

parsekwargs(kwargs) = kwargs
parsekwargs(::Nothing) = []

parsebody(body) = begin
    #HACK: disable return checking for now, too aggressive for local scope return
    #TODO: translate `return` to a local safe statement
    #MacroTools.postwalk(x -> @capture(x, return(_)) ? error("`return` is not allowed: $body") : x, body)
    body
end
parsebody(::Nothing) = nothing

parsestate(state) = typestate(Val(state))
typestate(::Val{S}) where {S} = Symbol(uppercasefirst(string(S)))
typestate(::Val{nothing}) = nothing

parsetype(::Nothing, ::Nothing, state, _, _) = typetag(Val(state))
parsetype(stype, ::Nothing, _, args...) = parsetype(Val(:static), stype, args...)
parsetype(::Nothing, dtype, _, args...) = parsetype(Val(:dynamic), dtype, args...)
parsetype(trait, type, scope, substs) = begin
    if haskey(substs, type)
        s = substs[type]
        type = s.type
        scope = s.scope
        #HACK: force static type when substituion takes place
        trait = Val(:static)
    end
    parsetype(type, scope, trait)
end
parsetype(type, scope, trait) = begin
    T = if @capture(type, elemtype_[])
        :(Vector{$(gentype(elemtype, scope, trait))})
    else
        gentype(type, scope, trait)
    end
end
gentype(type, scope, trait) = genactualtype(genscopedtype(type, scope), trait)
genscopedtype(type, scope) = begin
    l = Symbol[]
    add(t::Symbol) = push!(l, t)
    add(t) = nothing
    isexpr(type, :braces) && MacroTools.postwalk(type) do ex
        @capture(ex, $:|(T__)) && add.(T)
        ex
    end
    conv(t) = prefixscope(parsetypealias(t), scope)
    isempty(l) ? conv(type) : :(Union{$(conv.(l)...)})
end
genactualtype(type, ::Val{:static}) = :($C.typefor($type))
genactualtype(type, ::Val{:dynamic}) = type

parsetypealias(type::Symbol) = parsetypealias(Val(type), type)
parsetypealias(type) = type
parsetypealias(::Val{:int}, _) = :Int64
parsetypealias(::Val{:uint}, _) = :UInt64
parsetypealias(::Val{:float}, _) = :Float64
parsetypealias(::Val{:bool}, _) = :Bool
parsetypealias(::Val{:sym}, _) = :Symbol
parsetypealias(::Val{:str}, _) = :String
parsetypealias(::Val{:∅}, _) = :Nothing
parsetypealias(::Val{:_}, _) = :Missing
parsetypealias(::Val, type) = type

extractscope(x) = begin
    l = []
    if @capture(x, a_{c__})
        x = a
    end
    while true
        if @capture(x, a_.b_)
            push!(l, b)
            if isexpr(a)
                x = a
            else
                push!(l, a)
                break
            end
        else
            push!(l, x)
            break
        end
    end
    (; l=reverse(l), c)
end
genscope(lc) = genscope(lc.l, lc.c)
genscope(l, ::Nothing) = reduce((a, b) -> Expr(:., a, QuoteNode(b)), l)
genscope(l, c) = :($(genscope(l, nothing)){$(c...)})
prefixscope(x, p::Module) = prefixscope(x, nameof(p))
prefixscope(x, p::Symbol) = let (l, c) = extractscope(x)
    genscope([p, l...], c)
end

getmodule(m::Module, i) = reduce((a, b) -> getfield(a, b), split(String(i), ".") .|> Symbol, init=m)

parsetags(::Nothing; a...) = parsetags([]; a...)
parsetags(tags::Vector; state, type, a...) = begin
    s = Val(state)
    d = Dict{Symbol,Any}()
    for t in tags
        if @capture(t, k_=v_)
            d[k] = v
        elseif @capture(t, @u_str(v_))
            d[:unit] = @q @u_str($v)
        else
            d[t] = true
        end
    end
    !haskey(d, :unit) && (d[:unit] = nothing)
    d[:_type] = esc(type)
    updatetags!(d, s; a...)
    d
end

typetag(::Val) = :Float64
typetag(::Val{:Advance}) = :Float64 #HACK: avoid unexpected promotion (i.e. Rational) when using :Int
typetag(::Val{:Flag}) = :Bool
typetag(::Val{:Produce}) = :(Vector{System})
typetag(::Val{:Provide}) = :(Cropbox.DataFrame)
typetag(::Val{nothing}) = nothing

supportedtags(::Val) = nothing

filterconstructortags(v::VarInfo) = begin
    stags = constructortags(Val(v.state))
    filter(v.tags) do (k, v)
        isnothing(stags) ? true : k in stags ||
        startswith(String(k), "_")
    end
end

updatetags!(d, ::Val; _...) = nothing

istag(v::VarInfo, t) = get(v.tags, t, false)
istag(v::VarInfo, t::Tuple) = any(istag.(Ref(v), t))
istag(v::VarInfo, t...) = istag(v, t)
istag(t) = Base.Fix2(istag, t)
hastag(v::VarInfo, t) = haskey(v.tags, t)
gettag(v::VarInfo, t, d=nothing) = get(v.tags, t, d)

Base.names(v::VarInfo) = let n = v.name, a = v.alias
    isnothing(a) ? [n] : [n, a]
end
linenumber(v::VarInfo, prefix="", postfix="") = begin
    n = v.linenumber
    @set n.file = Symbol(n.file, ":$prefix|", v.name, "|$postfix")
end

####

abstract type VarStep end
struct PreStep <: VarStep end
struct MainStep <: VarStep end
struct PostStep <: VarStep end

Base.print(io::IO, ::PreStep) = print(io, "∘")
Base.print(io::IO, ::MainStep) = print(io, "")
Base.print(io::IO, ::PostStep) = print(io, "⋆")

struct Node{I,S}
    info::I
    step::S
end

const VarNode = Node{VarInfo,VarStep}

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

const C = :Cropbox
const ϵ = @q begin end

genvartype(v::VarInfo) = genvartype(v)
genvartype(v::VarInfo{Nothing}) = gettag(v, :_type)
genvartype(v::VarInfo{Symbol}) = begin
    N = gettag(v, :_type)
    U = gettag(v, :unit)
    V = @q $C.valuetype($N, $U)
    genvartype(v, Val(v.state); N, U, V)
end

genfield(v::VarInfo) = begin
    type = genvartype(v)
    name = symname(v)
    docstring = isempty(v.docstring) ? ϵ : v.docstring
    alias = v.alias
    @q begin
        $docstring
        $name::$type
        $(isnothing(alias) ? ϵ : docstring)
        $(isnothing(alias) ? ϵ : :($alias::$type))
    end
end
genfields(infos) = [genfield(v) for v in infos]

genpredecl(name) = @q _names = $C.names.($C.mixincollect($(esc(name)))) |> reverse |> Iterators.flatten |> collect
gennewargs(infos) = names.(infos) |> Iterators.flatten |> collect

genoverride(v::VarInfo) = begin
    !isnothing(v.body) && error("`override` can't have funtion body: $(v.body)")
    gengetkwargs(v, nothing)
end

genextern(v::VarInfo, default) = gengetkwargs(v, default)

gengetkwargs(v::VarInfo, default) = begin
    K = [Meta.quot(n) for n in names(v)]
    K = names(v)
    @q $C.getbynames(__kwargs__, $K, $default)
end

getbynames(d, K, default=nothing) = begin
    for k in K
        haskey(d, k) && return d[k]
    end
    default
end

using DataStructures: OrderedSet
gendecl(N::Vector{VarNode}) = gendecl.(OrderedSet([n.info for n in N]))
gendecl(v::VarInfo) = begin
    name = Meta.quot(v.name)
    alias = Meta.quot(v.alias)
    decl = if istag(v, :override)
        genoverride(v)
    else
        value = istag(v, :extern) ? genextern(v, gendefault(v)) : gendefault(v)
        stargs = [:($(esc(k))=$v) for (k, v) in filterconstructortags(v)]
        @q $C.$(v.state)(; _name=$name, _alias=$alias, _value=$value, $(stargs...))
    end
    gendecl(v, decl)
end
gendecl(v::VarInfo{Nothing}) = begin
    args = emitfuncargpair.(v.args; value=false)
    if istag(v, :option)
        push!(args, @q $(esc(:option)) = __kwargs__)
    end
    decl = if istag(v, :override)
        genoverride(v)
    elseif isnothing(v.body)
        @q $(esc(v.type))(; $(args...))
    else
        @q let $(args...); $(esc(v.body)) end
    end
    # implicit :expose
    decl = :($(esc(v.name)) = $decl)
    gendecl(v, decl)
end
gendecl(v::VarInfo, decl) = @q begin
    $(linenumber(v, "gendecl"))
    $(v.name) = $decl
    $(isnothing(v.alias) ? ϵ : :($(v.alias) = $(v.name)))
end

#HACK: @capture doesn't seem to support GlobalRef
const DOCREF = GlobalRef(Core, Symbol("@doc"))
isdoc(ex) = isexpr(ex, :macrocall) && ex.args[1] == DOCREF
gensource(v::VarInfo, name) = begin
    v.system != name && return ϵ
    if isempty(v.docstring)
        @q begin $(v.linenumber); $(v.line) end
    else
        Expr(:macrocall, DOCREF, v.linenumber, v.docstring, v.line)
    end
end
gensource(infos, name) = MacroTools.flatten(@q begin $(gensource.(infos, name)...) end)

updateconsts(consts, infos) = begin
    #HACK: keep type of Context in case needed for field construction (i.e. timeunit for Accumulate)
    context = filter(v -> v.name == :context, infos) |> only
    merge(consts, Dict(:__Context__ => context.type))
end
genconstpatches(consts, scope, incl) = begin
    @gensym CS
    consts0 = merge(constsof.(_mixincollect(mixinsof(scope, incl)))...)
    K = [keys(consts0)..., keys(consts)...]
    [
        :($CS = $(genconstbase(:(mixinsof($scope, $incl)), consts))),
        (:($k = $CS[$(Meta.quot(k))]) for k in K)...
    ]
end
genconstbase(M, consts) = :(merge(constsof.(_mixincollect($M))..., Dict($((@q($(Meta.quot(p[1])) => $(esc(p[2]))) for p in consts)...))))

genfieldnamesunique(infos) = Tuple(v.name for v in infos)
genfieldnamesalias(infos) = Tuple((v.name, v.alias) for v in infos)

genstruct(name, type, infos, consts, substs, incl, scope) = begin
    _S = esc(gensym(name))
    S = esc(name)
    T = esc(type)
    N = Meta.quot(name)
    nodes = sortednodes(infos)
    #HACK: field declarations inside block doesn't work as expected
    #fields = genfields(infos)
    fields = MacroTools.flatten(@q begin $(genfields(infos)...) end).args
    predecl = genpredecl(name)
    decls = gendecl(nodes)
    args = gennewargs(infos)
    source = gensource(infos, name)
    consts = updateconsts(consts, infos)
    constpatches = genconstpatches(consts, scope, incl)

    system = quote
        Core.@__doc__ abstract type $S <: $T end
        $S(; kw...) = $_S(; kw...)
        $C.typefor(::Type{<:$S}) = $_S
        let $(constpatches...)
            Core.@__doc__ mutable struct $_S <: $S
                $(fields...)
                function $_S(; __kwargs__...)
                    $predecl
                    $(decls...)
                    new($(args...))
                end
            end
        end
        $C.namefor(::Type{$_S}) = $C.namefor($S)
        $C.typefor(::Type{$_S}) = $_S
        $C.source(::Type{$_S}) = $(Meta.quot(source))
        $C.constsof(::Type{$_S}) = $(genconstbase(:(mixinsof($S)), consts))
        $C.substsof(::Type{$_S}) = $substs
        $C.mixinsof(::Type{$_S}) = $(mixinsof(scope, incl))
        $C.fieldnamesunique(::Type{$_S}) = $(genfieldnamesunique(infos))
        $C.fieldnamesalias(::Type{$_S}) = $(genfieldnamesalias(infos))
        $C.scopeof(::Type{$_S}) = $scope
        $C._update!($(esc(:self))::$_S, ::$C.MainStage) = $(genupdate(nodes, MainStage(); scope))
        $C._update!($(esc(:self))::$_S, ::$C.PreStage) = $(genupdate(infos, PreStage(); scope))
        $C._update!($(esc(:self))::$_S, ::$C.PostStage) = $(genupdate(infos, PostStage(); scope))
        Base.Docs.getdoc(::Type{$S}) = $C.getdoc($_S)
        Base.Docs.getdoc(::Type{$_S}) = $C.getdoc($_S)
        $S
    end
    system #|> MacroTools.flatten
end

source(s::S) where {S<:System} = source(S)
source(::Type{S}) where {S<:System} = source(typefor(S))
source(::Type{System}) = quote
    context ~ ::Context(override)
    config(context) => context.config ~ ::Config
end
source(::Type) = :()

constsof(s::S) where {S<:System} = constsof(S)
constsof(::Type{S}) where {S<:System} = constsof(typefor(S))
constsof(::Type{System}) = Dict()

substsof(s::S) where {S<:System} = substsof(S)
substsof(::Type{S}) where {S<:System} = substsof(typefor(S))
substsof(::Type{System}) = Dict()

mixinsof(s::S) where {S<:System} = mixinsof(S)
mixinsof(::Type{S}) where {S<:System} = mixinsof(typefor(S))
mixinsof(::Type{System}) = (System,)
mixinsof(::Type) = ()
mixinsof(scope::Module, incl) = Tuple(getmodule.(Ref(scope), incl))

using DataStructures: OrderedSet
mixincollect(s::S) where {S<:System} = mixincollect(S)
mixincollect(S::Type{<:System}, l=OrderedSet()) = begin
    S in l && return l
    push!(l, S)
    _mixincollect(mixinsof(S), l)
    #HACK: ensure mixins come before composite system
    #TODO: need testsets for mixins/mixincollect
    push!(delete!(l, S), S)
    l
end
_mixincollect(M::Tuple, l=OrderedSet()) = begin
    for m in M
        union!(l, mixincollect(m, l))
    end
    l
end
mixincollect(s) = ()

mixinof(s, SS::Type{<:System}...) = begin
    M = mixincollect(s)
    for S in SS
        for m in M
            m <: S && return S
        end
    end
    nothing
end

mixindispatch(s, SS::Type{<:System}...) = begin
    m = mixinof(s, SS...)
    n = isnothing(m) ? m : namefor(m)
    (s, Val(n))
end

typefor(s::Symbol, m::Module=Main) = getmodule(m, s) |> typefor
typefor(T) = T
vartype(::Type{S}, k) where {S<:System} = fieldtype(typefor(S), k) |> typefor

fieldnamesunique(::Type{System}) = ()
fieldnamesalias(::Type{System}) = ()
fieldnamesunique(::S) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::S) where {S<:System} = fieldnamesalias(S)
fieldnamesunique(::Type{S}) where {S<:System} = fieldnamesunique(typefor(S))
fieldnamesalias(::Type{S}) where {S<:System} = fieldnamesalias(typefor(S))

subsystemsof(::Type{System}) = ()
subsystemsof(::S) where {S<:System} = subsystemsof(S)
subsystemsof(::Type{S}) where {S<:System} = filter(n -> fieldtype(typefor(S), n) <: System, fieldnamesunique(S))

scopeof(::Type{System}) = @__MODULE__
scopeof(::S) where {S<:System} = scopeof(S)
scopeof(::Type{S}) where {S<:System} = scopeof(typefor(S))

abstract type UpdateStage end
struct PreStage <: UpdateStage end
struct MainStage <: UpdateStage end
struct PostStage <: UpdateStage end

Base.print(io::IO, ::PreStage) = print(io, "†")
Base.print(io::IO, ::MainStage) = print(io, "")
Base.print(io::IO, ::PostStage) = print(io, "‡")

_update!(S::Vector{<:System}, t) = begin
    for s in S
        update!(s, t)
    end
end
_update!(s, t) = s
update!(s, t=MainStage()) = _update!(s, t)

parsehead(head; scope) = begin
    # @system name[{patches..}][(mixins..)] [<: type]
    @capture(head, (decl_ <: type_) | decl_)
    @capture(decl, name_{patches__}(mixins__) | name_{patches__} | name_(mixins__) | name_)
    type = isnothing(type) ? :System : type
    patches = isnothing(patches) ? [] : patches
    mixins = isnothing(mixins) ? [] : mixins
    consts, substs = parsepatches(patches, scope)
    incl = [:System]
    for m in mixins
        push!(incl, Symbol(m))
    end
    (; name, consts, substs, incl, type)
end

parsepatches(patches::Vector, scope::Module) = begin
    consts = Dict()
    substs = Dict()
    for p in patches
        if @capture(p, o_ => n_)
            substs[o] = (; type=n, scope)
        elseif @capture(p, o_ = n_)
            consts[o] = n
        else
            error("unsupported patch format: $p")
        end
    end
    (consts, substs)
end

using DataStructures: OrderedDict, OrderedSet
gensystem(body; name, consts, substs, incl, type, scope, _...) = genstruct(name, type, geninfos(body; name, substs, incl, scope), consts, substs, incl, scope)
geninfos(body; name, substs, incl, scope, _...) = begin
    # update type substitution dict cascaded over all participating mixins
    substs = merge(substsof.(_mixincollect(mixinsof(scope, incl)))..., substs)
    con(b, s, sc) = begin
        d = OrderedDict{Symbol,VarInfo}()
        #HACK: default in case LineNumberNode is not attached
        ln = LineNumberNode(@__LINE__, @__FILE__)
        for l in b.args
            isline(l) && (ln = l; continue)
            if isdoc(l)
                lnn, ds, l = l.args[2:4]
                isline(lnn) && (ln = lnn)
            else
                ds = ""
            end
            v = VarInfo(s, l, ln, ds, sc, substs)
            d[v.name] = v
        end
        d
    end
    add!(d, b, s, sc) = begin
        for (n, v) in con(b, s, sc)
            if haskey(d, n)
                v0 = d[n]
                if v.state == :Hold
                    continue
                # support simple body replacement (i.e. `a => 1` without `~ ...` part)
                elseif isnothing(v.state) && isnothing(v.type)
                    v = @set v0.body = v.body
                elseif v0.alias != v.alias && v0.state != :Hold
                    @warn "variable replaced with inconsistent alias" name=v.name system=(v0.system => v.system) alias=(v0.alias => v.alias)
                end
            end
            d[n] = v
        end
    end
    combine() = begin
        d = OrderedDict{Symbol,VarInfo}()
        for i in incl
            S = getmodule(scope, i)
            for m in mixincollect(S)
                add!(d, source(m), namefor(m), scopeof(m))
            end
        end
        add!(d, body, name, scope)
        d
    end
    combine() |> values |> collect
end
geninfos(S::Type{<:System}) = geninfos(source(S); name=namefor(S), substs=substsof(S), incl=Symbol.(mixinsof(S)), scope=scopeof(S))

include("dependency.jl")
sortednodes(infos) = sort(dependency(infos))

"""
    @system name[{patches..}][(mixins..)] [<: type] [decl] -> Type{<:System}

Declare a new system called `name` with new variables declared in `decl` block using a custom syntax. The resultant system is subtype of `System` or a custom `type`. `mixins` allows reusing specification of existing systems to be pasted into the declaration of new system. `patches` may provide type substitution and/or constant definition needed for advanced use.

# Variable
    name[(args..; kwargs..)][: alias] [=> expr] [~ [state][::type|<:type][(tags..)]]

- `name`: variable name; usually short abbreviation.
- `args`: automatically bound depending variables
- `kwargs`: custom bound depending variables; used by `call` and `integrate`.
- `alias`: alternative name; long description.
- `expr`: state-specific code snippet; use begin-end block for multiple statements.
- `type`: internal data type; default is Float64 for many, but not all, variables.
- `tags`: state-specific options; `unit`, `min`/`max`, etc.

# States
- `hold`: marks a placeholder for variable shared between mixins.
- `wrap`: passes a state variable to other fucnction as is with no unwrapping its value.
- `advance`: manages a time-keeping variable; `time` and `tick` from `Clock`.
- `preserve`: keeps initially assigned value with no further updates; constants, parameters.
- `tabulate`: makes a two dimensional table with named keys; *i.e.* partitioning table.
- `interpolate`: makes a curve fuction interpolated with discrete values; *i.e.* soil characteristic curve.
- `track`: evaluates variable expression as is for each update.
- `remember`: keeps tracking variable until a certain condition is met; essentially `track` turning into `preserve`.
- `provide`: manages a table of time-series in DataFrame.
- `drive`: fetchs the current value from a time-series; maybe supplied by `provide`.
- `call`: defines a partial function bound with some variables.
- `integrate`: calculates integral using Gaussian method; not for time domain.
- `accumulate`: emulates integration of rate variable over time; essentially Euler method.
- `capture`: calculates difference between integration for each time step.
- `flag`: sets a boolean flag; essentially `track::Bool`.
- `produce`: attaches a new instance of system dynamically constructed; *i.e.* root structure growth.
- `bisect`: solves nonlinear equation using bisection method; *i.e.* gas-exchange model coupling.
- `solve`: solves polynomical equation symbolically; *i.e.* quadratic equations in photosynthesis model.

# Examples
```julia-repl
julia> @system S(Controller) begin
           a => 1 ~ preserve(parameter)
           b(a) ~ accumulate
       end
S
```
"""
macro system(head, body=:(begin end))
    scope = __module__
    gensystem(body; scope, parsehead(head; scope)...)
end

export @system, update!

gendefault(v::VarInfo) = gendefault(v, Val(v.state))
gendefault(v::VarInfo, ::Val) = gendefaultvalue(v)

gensample(v::VarInfo, x) = @q $C.sample($x)
genunitfy(v::VarInfo, x) = begin
    u = gettag(v, :unit)
    isnothing(u) ? x : @q $C.unitfy($x, $C.value($u))
end
genminmax(v::VarInfo, x) = begin
    l = gettag(v, :min)
    u = gettag(v, :max)
    #TODO: validate (min <= max)
    x = isnothing(l) ? x : @q max($(genunitfy(v, @q $C.value($l))), $x)
    x = isnothing(u) ? x : @q min($x, $(genunitfy(v, @q $C.value($u))))
    x
end
genround(v::VarInfo, x) = begin
    f = gettag(v, :round)
    isnothing(f) && return x
    f = if f isa Bool
        f ? :round : return x
    elseif f isa QuoteNode
        f.value
    else
        error("unsupported value for tag `round`: $f")
    end
    U = gettag(v, :roundunit)
    U = isnothing(U) ? gettag(v, :unit) : U
    N = gettag(v, :_type)
    if isnothing(U)
        #HACK: rounding functions with explicit type only supports Integer target
        # https://github.com/JuliaLang/julia/issues/37984
        @q convert($N, $f($x))
    else
        @q $f($C.valuetype($N, $U), $x)
    end
end
genwhen(v::VarInfo, x) = begin
    w = gettag(v, :when)
    isnothing(w) && return x
    N = gettag(v, :_type)
    U = gettag(v, :unit)
    @q $C.value($w) ? $x : zero($C.valuetype($N, $U))
end

genparameter(v::VarInfo) = begin
    @gensym o
    @q let $o = $C.option(config, _names, $(names(v)))
        ismissing($o) ? $(genbody(v)) : $o
    end
end
geninit(v::VarInfo) = @q $C.value($(gettag(v, :init)))

gendefaultvalue(v::VarInfo; parameter=false, init=false, sample=true, unitfy=true, minmax=true, round=true, when=true) = begin
    x = if parameter && istag(v, :parameter)
        genparameter(v)
    elseif init && hastag(v, :init)
        geninit(v)
    else
        genbody(v)
    end
    sample && (x = gensample(v, x))
    unitfy && (x = genunitfy(v, x))
    minmax && (x = genminmax(v, x))
    round && (x = genround(v, x))
    when && (x = genwhen(v, x))
    x
end

genupdate(nodes::Vector{VarNode}, ::MainStage; kw...) = @q begin
    $([genupdateinit(n.info; kw...) for n in nodes]...)
    $([genupdate(n; kw...) for n in nodes]...)
    self
end

genupdate(infos::Vector{VarInfo}, t::UpdateStage; kw...) = @q begin
    $([genupdateinit(v; kw...) for v in infos]...)
    $([genupdate(v, t; kw...) for v in infos]...)
    self
end

symname(v::VarInfo) = symname(v.system, v.name)
symname(s::Symbol, n::Symbol) = n #Symbol(:_, s, :__, n)
symstate(v::VarInfo) = symname(v) #Symbol(symname(v), :__state)
symsuffix(::T) where {T} = "__$T"
symlabel(v::VarInfo, t, s...) = Symbol(symname(v), symsuffix(t), s...)
symcall(v::VarInfo) = Symbol(v.name, :__call)

genupdateinit(v::VarInfo; kw...) = begin
    # implicit :expose
    @q begin
        $(v.name) = self.$(v.name)
        $(isnothing(v.alias) ? ϵ : :($(v.alias) = $(v.name)))
    end
end

genupdate(n::VarNode; kw...) = genupdate(n.info, n.step; kw...)
genupdate(v::VarInfo, t; kw...) = @q begin
    $(linenumber(v, "genupdate", t))
    @label $(symlabel(v, t))
    $(genupdate(v, Val(v.state), t; kw...))
end

genvalue(v::VarInfo) = @q $C.value($(symstate(v)))
genstore(v::VarInfo, val=nothing; unitfy=true, minmax=true, round=true, when=true) = begin
    isnothing(val) && (val = genbody(v))
    unitfy && (val = genunitfy(v, val))
    minmax && (val = genminmax(v, val))
    round && (val = genround(v, val))
    when && (val = genwhen(v, val))
    #TODO: remove redundant unitfy() in store!()
    @gensym s
    @q let $s = $(symstate(v))
        $C.store!($s, $val)
    end
end

genupdate(v::VarInfo, ::Val{nothing}, ::PreStep; kw...) = begin
    if istag(v, :context)
        @gensym c
        @q let $c = $(v.name)
            $C.update!(self, $C.PreStage())
            $c
        end
    end
end
genupdate(v::VarInfo, ::Val{nothing}, ::MainStep; kw...) = begin
    if istag(v, :override, :skip)
        nothing
    else
        @q $C.update!($(v.name))
    end
end
genupdate(v::VarInfo, ::Val{nothing}, ::PostStep; kw...) = begin
    if istag(v, :context)
        l = symlabel(v, PreStep())
        @gensym c cc
        @q let $c = $(v.name),
               $cc = $c.context
            $C.update!(self, $C.PostStage())
            if !isnothing($cc) && $C.value($c.clock.time) < $C.value($cc.clock.time)
                @goto $l
            end
            $c
        end
    end
end

genupdate(v::VarInfo, ::Val, ::PreStep; kw...) = nothing
genupdate(v::VarInfo, ::Val, ::MainStep; kw...) = istag(v, :override, :skip) ? nothing : genstore(v)
genupdate(v::VarInfo, ::Val, ::PostStep; kw...) = nothing

genupdate(v::VarInfo, ::Val, ::UpdateStage; kw...) = nothing
genupdate(v::VarInfo, ::Val{nothing}, ::PreStage; kw...) = @q $C.update!($(v.name), $C.PreStage())
genupdate(v::VarInfo, ::Val{nothing}, ::PostStage; kw...) = @q $C.update!($(v.name), $C.PostStage())

#TODO: merge extractfuncargdep() and extractfuncargkey()?
extractfuncargdep(v::Expr) = begin
    a = v.args
    if isexpr(v, :call)
        # detect boolean operators between state vars (i.e. `a`, `b` in `a && b`, `a || b`)
        if a[1] == :& || a[1] == :|
            extractfuncargdep.(a[2:3]) |> Iterators.flatten |> collect
        # detect variable inside wrapping function (i.e. `a` in `nounit(a.b, ..)`)
        else
            extractfuncargdep(a[2])
        end
    # detect shorthand syntax for calling value() (i.e. `a` in `a'` = `value(a)`)
    elseif isexpr(v, Symbol("'"))
        extractfuncargdep(a[1])
    # detect first callee of dot chaining (i.e. `a` in `a.b.c`)
    elseif isexpr(v, :., :ref)
        extractfuncargdep(a[1])
    else
        nothing
    end
end
extractfuncargdep(v::Symbol) = [v]
extractfuncargdep(v) = nothing

extractfuncargkey(v::Expr) = begin
    a = v.args
    if isexpr(v, :call)
        # detect boolean operators between state vars (i.e. `a`, `b` in `a && b`, `a || b`)
        if a[1] == :& || a[1] == :|
            error("missing function argument key: $v")
        # detect variable inside wrapping function (i.e. `b` in `nounit(a.b, ..)`)
        else
            extractfuncargkey(a[2])
        end
    # detect shorthand syntax for calling value() (i.e. `b` in `a.b'` = `value(a.b)`)
    elseif isexpr(v, Symbol("'"))
        extractfuncargkey(a[1])
    # detect last callee of dot chaining (i.e. `c` in `a.b.c`)
    elseif isexpr(v, :., :ref)
        extractfuncargkey(a[2])
    else
        error("unrecognized function argument key: $v")
    end
end
extractfuncargkey(v::QuoteNode) = extractfuncargkey(v.value)
extractfuncargkey(v::Symbol) = v

extractfuncargpair(a) = let k, v
    !@capture(a, k_=v_) && (k = a; v = a)
    extractfuncargkey(k) => v
end
emitfuncargpair(a; kw...) = emitfuncargpair(extractfuncargpair(a)...; kw...)
emitfuncargpair(k, v; value=true) = begin
    k = esc(k)
    v = value ? @q($C.value($v)) : v
    @q $k = $v
end

genbody(v::VarInfo, body=nothing) = begin
    if isnothing(v.body) && length(v.args) == 1
        a = v.args[1]
        #HACK: can't use or (|) syntax: https://github.com/MikeInnes/MacroTools.jl/issues/36
        if @capture(a, k_=v_)
            args = emitfuncargpair(k, v)
        elseif @capture(a, k_Symbol)
            args = emitfuncargpair(k, k)
        else
            @gensym k
            args = emitfuncargpair(k, a)
        end
        body = esc(k)
    else
        args = @q begin $(emitfuncargpair.(v.args)...) end
        isnothing(body) && (body = esc(v.body))
    end
    MacroTools.flatten(@q let $args; $body end)
end

extractfunckwargtuple(a) = let k, t, u
    @capture(a, k_::t_(u_) | k_::t_ | k_(u_))
    isnothing(k) && (k = a)
    (k, t, u)
end
emitfunckwargkey(a) = @q $(esc(extractfunckwargtuple(a)[1]))
emitfunckwargpair(a) = begin
    k, t, u = extractfunckwargtuple(a)
    v = esc(k)
    v = isnothing(u) ? @q($v) : @q($C.unitfy($v, $u))
    # Skip type assertion (maybe only needed for Call, not Integrate)
    #v = @q $v::$C.valuetype($(gencallargtype(t)), $u)
    @q $k = $v
end

genfunc(v::VarInfo; unitfy=true) = begin
    innerargs = @q begin $(emitfuncargpair.(v.args)...) end
    innerbody = MacroTools.flatten(@q let $innerargs; $(esc(v.body)) end)
    unitfy && (innerbody = @q $C.unitfy($innerbody, $C.value($(gettag(v, :unit)))))

    callargs = emitfunckwargkey.(v.kwargs)
    argsheader = emitfunckwargpair.(v.kwargs)

    @q function $(symcall(v))($(callargs...))
        let $(argsheader...)
            $innerbody
        end
    end
end
