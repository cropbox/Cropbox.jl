using MacroTools
import MacroTools: @q
import Setfield: @set

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
    line::Union{Expr,Symbol}
    linenumber::LineNumberNode
end

import Base: show
show(io::IO, v::VarInfo) = begin
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
end

VarInfo(system::Symbol, line::Union{Expr,Symbol}, linenumber::LineNumberNode) = begin
    # name[(args..; kwargs..)][: alias] [=> body] [~ [state][::type][(tags..)]]
    @capture(line, (decl_ ~ deco_) | decl_)
    @capture(deco, state_::type_(tags__) | ::type_(tags__) | state_(tags__) | state_::type_ | ::type_ | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: alias_) | def2_)
    @capture(def2, name_(args__; kwargs__) | name_(; kwargs__) | name_(args__) | name_)
    args = isnothing(args) ? [] : args
    kwargs = isnothing(kwargs) ? [] : kwargs
    state = isnothing(state) ? nothing : Symbol(uppercasefirst(string(state)))
    type = @capture(type, [elemtype_]) ? :(Vector{$elemtype}) : isnothing(type) ? typetag(Val(state)) : type
    tags = parsetags(tags; name=name, alias=alias, args=args, kwargs=kwargs, state=state, type=type)
    VarInfo{typeof(state)}(system, name, alias, args, kwargs, body, state, type, tags, line, linenumber)
end

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
typetag(::Val{:Produce}) = :System
typetag(::Val{nothing}) = nothing

updatetags!(d, ::Val; _...) = nothing

istag(v::VarInfo, t) = get(v.tags, t, false)
istag(v::VarInfo, t...) = any(istag.(Ref(v), t))
gettag(v::VarInfo, t, d=nothing) = get(v.tags, t, d)

names(v::VarInfo) = let n = v.name, a = v.alias
    isnothing(a) ? [n] : [n, a]
end
linenumber(v::VarInfo, prefix="") = begin
    n = v.linenumber
    @set n.file = Symbol(n.file, ":$prefix|", v.name)
end

####

abstract type VarStep end
struct PreStep <: VarStep end
struct MainStep <: VarStep end
struct PostStep <: VarStep end

suffix(::PreStep) = "__pre"
suffix(::MainStep) = "__main"
suffix(::PostStep) = "__post"

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

const C = :($(esc(:Cropbox)))

genvartype(v::VarInfo) = genvartype(v)
genvartype(v::VarInfo{Nothing}) = esc(v.type)
genvartype(v::VarInfo{Symbol}) = begin
    N = gettag(v, :_type)
    U = gettag(v, :unit)
    V = @q $C.valuetype($N, $U)
    genvartype(v, Val(v.state); N=N, U=U, V=V)
end

genfield(type, name, alias) = @q begin
    $name::$type
    $(isnothing(alias) ? :(;) : :($alias::$type))
end
genfield(v::VarInfo) = genfield(genvartype(v), symname(v), v.alias)
genfields(infos) = [genfield(v) for v in infos]

genpredecl(name) = @q _names = $C.names.([$C.mixins($name)..., $name]) |> Iterators.flatten |> collect |> reverse
gennewargs(infos) = names.(infos) |> Iterators.flatten |> collect

genoverride(v::VarInfo) = begin
    !isnothing(v.body) && error("`override` can't have funtion body: $(v.body)")
    gengetkwargs(v, nothing)
end

genextern(v::VarInfo, default) = gengetkwargs(v, default)

gengetkwargs(v::VarInfo, default) = begin
    K = [Meta.quot(n) for n in names(v)]
    K = names(v)
    @q $C.getbynames(_kwargs, $K, $default)
end

getbynames(d, K, default=nothing) = begin
    for k in K
        haskey(d, k) && return d[k]
    end
    default
end

import DataStructures: OrderedSet
gendecl(N::Vector{VarNode}) = gendecl.(OrderedSet([n.info for n in N]))
gendecl(v::VarInfo{Symbol}) = begin
    name = Meta.quot(v.name)
    alias = Meta.quot(v.alias)
    decl = if istag(v, :override)
        genoverride(v)
    else
        value = istag(v, :extern) ? genextern(v, geninit(v)) : geninit(v)
        stargs = [:($(esc(k))=$v) for (k, v) in v.tags]
        @q $C.$(v.state)(; _name=$name, _alias=$alias, _value=$value, $(stargs...))
    end
    gendecl(v, decl)
end
gendecl(v::VarInfo{Nothing}) = begin
    emit(a) = (p = extractfuncargpair(a); @q $(esc(p[1])) = $(p[2]))
    args = emit.(v.args)
    if istag(v, :option)
        push!(args, @q $(esc(:option)) = _kwargs)
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
    $(isnothing(v.alias) ? :(;) : :($(v.alias) = $(v.name)))
end

gensource(infos) = begin
    l = [@q begin $(v.linenumber); $(v.line) end for v in infos]
    MacroTools.flatten(@q begin $(l...) end)
end

genfieldnamesunique(infos) = Tuple(v.name for v in infos)
genfieldnamesalias(infos) = Tuple((v.name, v.alias) for v in infos)

genstruct(name, type, infos, incl) = begin
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
    source = gensource(infos)
    system = quote
        mutable struct $S <: $T
            $(fields...)
            function $name(; _kwargs...)
                $predecl
                $(decls...)
                new($(args...))
            end
        end
        $C.source(::Val{$N}) = $(Meta.quot(source))
        $C.mixins(::Val{$N}) = Tuple($(esc(:eval)).($incl))
        $C.type(::Val{$N}) = $S
        $C.fieldnamesunique(::Type{<:$S}) = $(genfieldnamesunique(infos))
        $C.fieldnamesalias(::Type{<:$S}) = $(genfieldnamesalias(infos))
        $C.update!($(esc(:self))::$S) = $(genupdate(nodes))
        $S
    end
    system #|> MacroTools.flatten
end

#TODO: maybe need to prevent naming clash by assigning UUID for each System
source(s::S) where {S<:System} = source(S)
source(S::Type{<:System}) = source(nameof(S))
source(s::Symbol) = source(Val(s))
source(::Val{:System}) = quote
    context ~ ::Cropbox.Context(override)
    config(context) => context.config ~ ::Cropbox.Config
end
source(::Val) = :()

mixins(s::S) where {S<:System} = mixins(S)
mixins(S::Type{<:System}) = mixins(nameof(S))
mixins(s::Symbol) = mixins(Val(s))
mixins(::Val{:System}) = (System,)
mixins(::Val) = ()

import DataStructures: OrderedSet
mixincollect(s::S) where {S<:System} = mixincollect(S)
mixincollect(S::Type{<:System}, l=OrderedSet()) = begin
    S in l && return l
    push!(l, S)
    for m in mixins(S)
        union!(l, mixincollect(m, l))
    end
    l
end
mixincollect(s) = ()
mixindispatch(s, S::Type{<:System}) = (Val(S in mixincollect(s) ? nameof(S) : nothing), s)

type(s::Symbol) = type(Val(s))

fieldnamesunique(::Type{<:System}) = ()
fieldnamesalias(::Type{<:System}) = ()

fieldnamesunique(::S) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::S) where {S<:System} = fieldnamesalias(S)

update!(S::Vector{<:System}) = begin
    #HACK: preliminary support for multi-threaded update! (could be much slower if update is small)
    Threads.@threads for s in S
        update!(s)
    end
end
update!(s) = s

parsehead(head) = begin
    # @system name[(mixins..)] [<: type]
    @capture(head, (decl_ <: type_) | decl_)
    @capture(decl, name_(mixins__) | name_)
    type = isnothing(type) ? :System : type
    mixins = isnothing(mixins) ? [] : mixins
    incl = [:System]
    for m in mixins
        push!(incl, m)
    end
    #TODO: use implicit named tuple once implemented: https://github.com/JuliaLang/julia/pull/34331
    (; name=name, incl=incl, type=type)
end

import DataStructures: OrderedDict, OrderedSet
gensystem(body; name, incl, type, _...) = genstruct(name, type, geninfos(body; name=name, incl=incl), incl)
geninfos(body; name, incl, _...) = begin
    con(b, s) = begin
        d = OrderedDict{Symbol,VarInfo}()
        #HACK: default in case LineNumberNode is not attached
        ln = LineNumberNode(@__LINE__, @__FILE__)
        for l in b.args
            if l isa LineNumberNode
                ln = l
            else
                v = VarInfo(s, l, ln)
                d[v.name] = v
            end
        end
        d
    end
    add!(d, b, s) = begin
        for (n, v) in con(b, s)
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
        for m in incl
            add!(d, source(m), m)
        end
        add!(d, body, name)
        d
    end
    combine() |> values |> collect
end
geninfos(S::Type{<:System}) = geninfos(source(S); name=nameof(S), incl=())

include("dependency.jl")
sortednodes(infos) = sort(dependency(infos))

macro system(head, body=:(begin end))
    gensystem(body; parsehead(head)...)
end

macro infos(head, body)
    geninfos(body; parsehead(head)...)
end

export @system, update!

geninit(v::VarInfo) = geninit(v, Val(v.state))
geninit(v::VarInfo, ::Val) = geninitvalue(v)

gensample(v::VarInfo, x) = @q $C.sample($x)
genunitfy(v::VarInfo, x) = begin
    u = gettag(v, :unit)
    isnothing(u) ? x : @q $C.unitfy($x, $C.value($u))
end
genminmax(v::VarInfo, x) = begin
    l = gettag(v, :min)
    u = gettag(v, :max)
    #TODO: validate (min <= max)
    x = isnothing(l) ? x : @q max($(genunitfy(v, l)), $x)
    x = isnothing(u) ? x : @q min($x, $(genunitfy(v, u)))
    x
end
geninitvalue(v::VarInfo; parameter=false, sample=true, unitfy=true, minmax=true) = begin
    s(x) = sample ? gensample(v, x) : x
    u(x) = unitfy ? genunitfy(v, x) : x
    m(x) = minmax ? genminmax(v, x) : x
    f(x) = x |> s |> u |> m
    if parameter && istag(v, :parameter)
        @gensym o
        x = @q ismissing($o) ? $(genfunc(v)) : $o
        @q let $o = $C.option(config, _names, $(names(v)))
            $(f(x))
        end
    else
        f(genfunc(v))
    end
end

genupdate(nodes) = @q begin
    $([genupdateinit(n) for n in nodes]...)
    $([genupdate(n) for n in nodes]...)
    self
end

symname(v::VarInfo) = symname(v.system, v.name)
symname(s::Symbol, n::Symbol) = n #Symbol(:_, s, :__, n)
symstate(v::VarInfo) = symname(v) #Symbol(symname(v), :__state)
symlabel(v::VarInfo, t::VarStep, s...) = Symbol(symname(v), suffix(t), s...)
symcall(v::VarInfo) = Symbol(v.name, :__call)

genupdateinit(n::VarNode) = begin
    v = n.info
    # implicit :expose
    @q begin
        $(v.name) = self.$(v.name)
        $(isnothing(v.alias) ? :(;) : :($(v.alias) = $(v.name)))
    end
end

genupdate(n::VarNode) = genupdate(n.info, n.step)
genupdate(v::VarInfo, t::VarStep) = @q begin
    $(linenumber(v, "genupdate"))
    @label $(symlabel(v, t))
    $(genupdate(v, Val(v.state), t))
end

genvalue(v::VarInfo) = :($C.value($(symstate(v))))
genstore(v::VarInfo) = begin
    @gensym s f
    @q let $s = $(symstate(v)),
           $f = $(genfunc(v))
        $C.store!($s, $f)
    end
end

genupdate(v::VarInfo, ::Val{nothing}, ::PreStep) = begin
    if istag(v, :context)
        @gensym c
        @q let $c = $(v.name)
            $C.preflush!($c.queue)
            $c
        end
    end
end
genupdate(v::VarInfo, ::Val{nothing}, ::MainStep) = begin
    if istag(v, :override, :skip)
        nothing
    else
        @q $C.update!($(v.name))
    end
end
genupdate(v::VarInfo, ::Val{nothing}, ::PostStep) = begin
    if istag(v, :context)
        l = symlabel(v, PreStep())
        @gensym c cc
        @q let $c = $(v.name),
               $cc = $c.context
            $C.postflush!($c.queue)
            if !isnothing($cc) && $C.value($c.clock.tick) < $C.value($cc.clock.tick)
                @goto $l
            end
            $c
        end
    end
end

genupdate(v::VarInfo, ::Val, ::PreStep) = genvalue(v)
genupdate(v::VarInfo, ::Val, ::MainStep) = istag(v, :override, :skip) ? genvalue(v) : genstore(v)
genupdate(v::VarInfo, ::Val, ::PostStep) = nothing

#TODO: merge extractfuncargdep() and extractfuncargkey()?
extractfuncargdep(v::Expr) = begin
    a = v.args
    # detect variable inside wrapping function (i.e. `a` in `nounit(a.b, ..)`)
    if isexpr(v, :call)
        extractfuncargdep(a[2])
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
extractfuncargdep(v::Symbol) = v
extractfuncargdep(v) = nothing

extractfuncargkey(v::Expr) = begin
    a = v.args
    # detect variable inside wrapping function (i.e. `b` in `nounit(a.b, ..)`)
    if isexpr(v, :call)
        extractfuncargkey(a[2])
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

genfuncargs(v::VarInfo) = begin
    emit(a) = let p = extractfuncargpair(a)
        @q $(esc(p[1])) = $C.value($(p[2]))
    end
    @q begin $(emit.(v.args)...) end
end
genfunc(v::VarInfo) = begin
    if isnothing(v.body) && length(v.args) == 1
        a = v.args[1]
        emit(k, v) = @q $(esc(k)) = $C.value($v)
        #HACK: can't use or (|) syntax: https://github.com/MikeInnes/MacroTools.jl/issues/36
        if @capture(a, k_=v_)
            args = emit(k, v)
        elseif @capture(a, k_Symbol)
            args = emit(k, k)
        else
            @gensym k
            args = emit(k, a)
        end
        body = esc(k)
    else
        args = genfuncargs(v)
        body = esc(v.body)
    end
    MacroTools.flatten(@q let $args; $body end)
end
