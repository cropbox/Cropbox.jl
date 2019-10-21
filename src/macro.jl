using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S<:Union{Symbol,Nothing}}
    system::Symbol
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
end

VarInfo(line::Union{Expr,Symbol}, system::Symbol) = begin
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
    tags = parsetags(tags; name=name, alias=alias, args=args, kwargs=kwargs, state=state, type=type)
    VarInfo{typeof(state)}(system, name, alias, args, kwargs, body, state, type, tags, line)
end

parsetags(::Nothing; a...) = parsetags([]; a...)
parsetags(tags::Vector; state, type, a...) = begin
    s = Val(state)
    d = Dict{Symbol,Any}()
    for t in tags
        if @capture(t, k_=v_)
            d[k] = v
        elseif @capture(t, @u_str(v_))
            d[:unit] = :@u_str($v)
        else
            d[t] = true
        end
    end
    !haskey(d, :unit) && (d[:unit] = nothing)
    d[:_type] = isnothing(type) ? typetag(s) : esc(type)
    updatetags!(d, s; a...)
    d
end

typetag(::Val) = :Float64
typetag(::Val{:Advance}) = :Int
typetag(::Val{:Flag}) = :Bool
typetag(::Val{:Produce}) = :System

updatetags!(d, ::Val; _...) = nothing
updatetags!(d, ::Val{:Interpolate}; _...) = begin
    !haskey(d, :reverse) && (d[:reverse] = false)
    !haskey(d, :knotunit) && (d[:knotunit] = nothing)
end
updatetags!(d, ::Union{Val{:Accumulate},Val{:Capture}}; _...) = begin
    !haskey(d, :time) && (d[:time] = :(context.clock.tick))
end
updatetags!(d, ::Val{:Call}; kwargs, _...) = begin
    #FIXME: lower duplicate efforts in genvartype()
    N = d[:_type]
    U = d[:unit]
    V = @q $C.valuetype($N, $U)
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        t = isnothing(t) ? :Float64 : esc(t)
        @q $C.valuetype($t, $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(kwargs)...)}}
    d[:_calltype] = F
end

istag(v::VarInfo, t) = get(v.tags, t, false)
istag(v::VarInfo, t...) = any(istag.(Ref(v), t))
gettag(v::VarInfo, t, d=nothing) = get(v.tags, t, d)

names(v::VarInfo) = [v.name, v.alias...]

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
    N = isnothing(v.type) ? :Float64 : esc(v.type)
    U = gettag(v, :unit)
    V = @q $C.valuetype($N, $U)
    genvartype(v, Val(v.state); N=N, U=U, V=V)
end
genvartype(v::VarInfo, ::Val{:Hold}; _...) = @q Hold{Any}
genvartype(v::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}
genvartype(v::VarInfo, ::Val{:Preserve}; V, _...) = @q Preserve{$V}
genvartype(v::VarInfo, ::Val{:Tabulate}; V, _...) = @q Tabulate{$V}
genvartype(v::VarInfo, ::Val{:Interpolate}; V, U, _...) = @q Interpolate{$V}
genvartype(v::VarInfo, ::Val{:Track}; V, _...) = @q Track{$V}
genvartype(v::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}
genvartype(v::VarInfo, ::Val{:Call}; V, _...) = begin
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        t = isnothing(t) ? :Float64 : esc(t)
        @q $C.valuetype($t, $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(v.kwargs)...)}}
    @q Call{$V,$F}
end
genvartype(v::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    #TODO: automatic inference without explicit `timeunit` tag
    TU = gettag(v, :timeunit)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end
genvartype(v::VarInfo, ::Val{:Capture}; N, U, V, _...) = begin
    TU = gettag(v, :timeunit)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Capture{$V,$T,$R}
end
genvartype(v::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}
genvartype(v::VarInfo, ::Val{:Produce}; _...) = begin
    S = isnothing(v.type) ? :System : esc(v.type)
    @q Produce{$S}
end
genvartype(v::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

gencall(v::VarInfo) = gencall(v, Val(v.state))
gencall(v::VarInfo, ::Val) = nothing
gencall(v::VarInfo, ::Val{:Call}) = begin
    args = genfuncargs(v)
    body = flatten(@q let $args; $(v.body) end)
    @q function $(symcall(v))($(v.kwargs...)) $body end
end
gencalls(infos) = filter(!isnothing, gencall.(infos))

genfield(type, name, alias) = @q begin
    $name::$type
    $(@q begin $([:($a::$type) for a in alias]...) end)
end
genfield(v::VarInfo) = genfield(genvartype(v), symname(v), v.alias)
genfields(infos) = [genfield(v) for v in infos]

genpredecl(name) = @q _names = $C.names.([$C.mixins($name)..., $name]) |> Iterators.flatten |> collect |> reverse
gennewargs(infos) = names.(infos) |> Iterators.flatten |> collect

genoverride(v::VarInfo) = begin
    !isnothing(v.body) && error("`override` can't have funtion body: $(v.body)")
    genoverride(v.name)
end
genoverride(name) = @q _kwargs[$(Meta.quot(name))]

genextern(name, default) = begin
    key = Meta.quot(name)
    @q haskey(_kwargs, $key) ? _kwargs[$key] : $default
end

import DataStructures: OrderedSet
gendecl(N::Vector{VarNode}) = gendecl.(OrderedSet([n.info for n in N]))
gendecl(v::VarInfo{Symbol}) = begin
    name = Meta.quot(v.name)
    alias = Tuple(v.alias)
    decl = if istag(v, :override)
        genoverride(v)
    else
        value = istag(v, :extern) ? genextern(v.name, geninit(v)) : geninit(v)
        stargs = [:($(esc(k))=$v) for (k, v) in v.tags]
        @q $C.$(v.state)(; _name=$name, _alias=$alias, _value=$value, $(stargs...))
    end
    gendecl(decl, v.name, v.alias)
end
gendecl(v::VarInfo{Nothing}) = begin
    pair(a) = let k, v; @capture(a, k_=v_) ? k => v : a => a end
    emit(a) = (p = pair(a); @q $(esc(p[1])) = $(p[2]))
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
    gendecl(decl, v.name, v.alias)
end
gendecl(decl, var, alias) = @q begin
    $(LineNumberNode(0, "gendecl/$var"))
    $var = $decl
    $(@q begin $([:($a = $var) for a in alias]...) end)
end

gensource(infos) = begin
    l = [v.line for v in infos]
    striplines(flatten(@q begin $(l...) end))
end

genfieldnamesunique(infos) = Tuple(v.name for v in infos)
genfieldnamesalias(infos) = Tuple((v.name, Tuple(v.alias)) for v in infos)

genstruct(name, infos, incl) = begin
    S = esc(name)
    N = Meta.quot(name)
    nodes = sortednodes(name, infos)
    calls = gencalls(infos)
    fields = genfields(infos)
    predecl = genpredecl(name)
    decls = gendecl(nodes)
    args = gennewargs(infos)
    source = gensource(infos)
    system = @q begin
        mutable struct $name <: $C.System
            $(fields...)
            function $name(; _kwargs...)
                $predecl
                $(decls...)
                new($(args...))
            end
        end
        $C.source(::Val{$N}) = $(Meta.quot(source))
        $C.mixins(::Val{$N}) = Tuple($(esc(:eval)).($incl))
        $C.fieldnamesunique(::Type{<:$S}) = $(genfieldnamesunique(infos))
        $C.fieldnamesalias(::Type{<:$S}) = $(genfieldnamesalias(infos))
        $C.update!($(esc(:self))::$S) = $(genupdate(nodes))
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

mixins(s::S) where {S<:System} = mixins(S)
mixins(S::Type{<:System}) = mixins(nameof(S))
mixins(s::Symbol) = mixins(Val(s))
mixins(::Val{:System}) = (System,)

fieldnamesunique(::Type{<:System}) = ()
fieldnamesalias(::Type{<:System}) = ()

fieldnamesunique(::S) where {S<:System} = fieldnamesunique(S)
fieldnamesalias(::S) where {S<:System} = fieldnamesalias(S)

import ProgressMeter: @showprogress
update!(s::System, n) = begin
    @showprogress for i in 1:n
        update!(s)
    end
end
update!(s::Vector{<:System}) = update!.(s)
update!(s) = s

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
gensystem(name, incl, body) = genstruct(name, geninfos(name, incl, body), incl)
geninfos(name, incl, body) = begin
    con(b, s) = OrderedDict(v.name => v for v in VarInfo.(striplines(b).args, s))
    add!(d, b, s) = begin
        for (n, v) in con(b, s)
            if haskey(d, n)
                if v.state == :Hold
                    continue
                end
            end
            d[n] = v
        end
    end
    d = OrderedDict{Symbol,VarInfo}()
    for m in incl
        add!(d, source(m), m)
    end
    add!(d, body, name)
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

macro system(head, body=:(begin end))
    gensystem(head, body)
end

macro infos(head, body)
    geninfos(parsehead(head)..., body)
end

export @system, update!

geninit(v::VarInfo) = geninit(v, Val(v.state))
geninit(v::VarInfo, ::Val) = @q $C.unitfy($(genfunc(v)), $C.value($(v.tags[:unit])))
geninit(v::VarInfo, ::Val{:Hold}) = nothing
geninit(v::VarInfo, ::Val{:Advance}) = missing
geninit(v::VarInfo, ::Val{:Preserve}) = geninitpreserve(v)
geninit(v::VarInfo, ::Val{:Tabulate}) = geninitpreserve(v)
geninitpreserve(v::VarInfo) = begin
    if istag(v, :parameter)
        @gensym o
        @q let $o = $C.option(config, _names, $(names(v)))
            $C.unitfy(isnothing($o) ? $(genfunc(v)) : $o, $C.value($(v.tags[:unit])))
        end
    else
        @q $C.unitfy($(genfunc(v)), $C.value($(v.tags[:unit])))
    end
end
#TODO: make use of geninitpreserve with unitfy turned off
geninit(v::VarInfo, ::Val{:Interpolate}) = begin
    if istag(v, :parameter)
        @gensym o
        @q let $o = $C.option(config, _names, $(names(v)))
            isnothing($o) ? $(genfunc(v)) : $o
        end
    else
        @q $(genfunc(v))
    end
end
geninit(v::VarInfo, ::Val{:Drive}) = begin
    k = gettag(v, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @q $C.unitfy($C.value($(genfunc(v))[$k]), $C.value($(v.tags[:unit])))
end
geninit(v::VarInfo, ::Val{:Call}) = begin
    pair(a) = let k, v; @capture(a, k_=v_) ? k => v : a => a end
    emiti(a) = (p = pair(a); @q $(esc(p[1])) = $C.value($(p[2])))
    innerargs = @q begin $(emiti.(v.args)...) end

    innercall = flatten(@q let $innerargs; $(esc(v.body)) end)
    innerbody = @q $C.unitfy($innercall, $C.value($(v.tags[:unit])))

    emito(a) = (p = pair(a); @q $(esc(p[1])) = $(p[2]))
    outerargs = @q begin $(emito.(v.args)...) end

    extract(a) = let k, t, u; @capture(a, k_::t_(u_) | k_::t_ | k_(u_)) ? k : a end
    emitc(a) = @q $(esc(extract(a)))
    callargs = emitc.(v.kwargs)

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
    # fillargs = emitf.(v.args)
    #
    # @q function $(symcall(v))($(fillargs...); $(callargs...)) $outerbody end
end
geninit(v::VarInfo, ::Val{:Accumulate}) = @q $C.unitfy($C.value($(gettag(v, :init))), $C.value($(v.tags[:unit])))
geninit(v::VarInfo, ::Val{:Capture}) = nothing
geninit(v::VarInfo, ::Val{:Flag}) = false
geninit(v::VarInfo, ::Val{:Produce}) = nothing
geninit(v::VarInfo, ::Val{:Solve}) = nothing
geninit(v::VarInfo, ::Val{:Resolve}) = @q $C.unitfy($C.value($(gettag(v, :init))), $C.value($(v.tags[:unit])))

####

genupdate(nodes) = @q begin
    $([genupdateinit(n) for n in nodes]...)
    $([genupdate(n) for n in nodes]...)
    self
end

symname(v::VarInfo) = symname(v.system, v.name)
symname(s::Symbol, n::Symbol) = n #Symbol(:_, s, :__, n)
symstate(v::VarInfo) = Symbol(symname(v), :__state)
symlabel(v::VarInfo, t::VarStep, s...) = Symbol(symname(v), suffix(t), s...)
symcall(v::VarInfo) = Symbol(v.name, :__call)

genupdateinit(n::VarNode) = begin
    v = n.info
    if isnothing(v.state)
        # implicit :expose
        @q begin
            $(v.name) = self.$(v.name)
            $([:($a = $(v.name)) for a in v.alias]...)
        end
    else
        s = symstate(v)
        @q $s = self.$(v.name)
    end
end

genupdate(n::VarNode) = genupdate(n.info, n.step)
genupdate(v::VarInfo, t::VarStep) = begin
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

genupdate(v::VarInfo, ::Val{:Advance}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.advance!($s)
    end
end

genupdate(v::VarInfo, ::Val{:Preserve}, ::MainStep) = genvalue(v)

genupdate(v::VarInfo, ::Val{:Tabulate}, ::MainStep) = genvalue(v)

genupdate(v::VarInfo, ::Val{:Interpolate}, ::MainStep) = genvalue(v)

genupdate(v::VarInfo, ::Val{:Drive}, ::MainStep) = begin
    k = gettag(v, :key, v.name)
    #HACK: needs quot if key is a symbol from VarInfo name
    k = isa(k, QuoteNode) ? k : Meta.quot(k)
    @gensym s f d
    @q let $s = $(symstate(v)),
           $f = $(genfunc(v)),
           $d = $C.value($f[$k])
        $C.store!($s, $d)
    end # value() for Var
end

genupdate(v::VarInfo, ::Val{:Call}, ::MainStep) = begin
    @gensym s
    @q let $s = $(symstate(v))
        $C.value($s)
    end
end

genupdate(v::VarInfo, ::Val{:Accumulate}, ::MainStep) = begin
    @gensym s t t0 a
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $t0 = $s.tick,
           $a = $s.value + $s.rate * ($t - $t0)
        $C.store!($s, $a)
    end
end
genupdate(v::VarInfo, ::Val{:Accumulate}, ::PostStep) = begin
    @gensym s t f r q
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s)),
           $q = context.queue
        $C.queue!($q, () -> ($s.tick = $t; $s.rate = $r), $C.priority($C.$(v.state)))
    end
end

genupdate(v::VarInfo, ::Val{:Capture}, ::MainStep) = begin
    @gensym s t t0 d
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $t0 = $s.tick,
           $d = $s.rate * ($t - $t0)
        $C.store!($s, $d)
    end
end
genupdate(v::VarInfo, ::Val{:Capture}, ::PostStep) = begin
    @gensym s t f r q
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s)),
           $q = context.queue
        $C.queue!($q, () -> ($s.tick = $t; $s.rate = $r), $C.priority($C.$(v.state)))
    end
end

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = genvalue(v)
genupdate(v::VarInfo, ::Val{:Flag}, ::PostStep) = begin
    @gensym s f q
    if istag(v, :oneway)
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v)),
               $q = context.queue
            if !$C.value($s)
                $C.queue!($q, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
            end
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v)),
               $q = context.queue
            $C.queue!($q, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
        end
    end
end

# Produce referenced in args expected to be raw state, not extracted by value(), for querying
genupdate(v::VarInfo, ::Val{:Produce}, ::PreStep) = symstate(v)
genupdate(v::VarInfo, ::Val{:Produce}, ::MainStep) = begin
    @gensym s b
    @q let $s = $(symstate(v))
        for $b in $C.value($s)
            $C.update!($b)
        end
        $s
    end
end
genupdate(v::VarInfo, ::Val{:Produce}, ::PostStep) = begin
    @gensym s P c o q a b
    @q let $s = $(symstate(v)),
           $P = $(genfunc(v)),
           $c = context,
           $q = context.queue,
           $a = $C.value($s)
        if !(isnothing($P) || isempty($P))
            $C.queue!($q, function ()
                for p in $P
                    $b = p.type(; context=$c, p.args...)
                    append!($a, $b)
                end
            end, $C.priority($C.$(v.state)))
        end
    end
end

genupdate(v::VarInfo, ::Val{:Solve}, ::MainStep) = begin
    N_MAX = 100
    TOL = 0.0001
    lstart = symlabel(v, PreStep())
    lexit = symlabel(v, MainStep(), :__exit)
    @gensym s d
    @q let $s = $(symstate(v))
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
            if $s.fc ≈ zero($s.fc) || ($s.b - $s.a) / ($s.b) < $TOL
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

genfuncargs(v::VarInfo) = begin
    pair(a) = let k, v; @capture(a, k_=v_) ? k => v : a => a end
    emit(a) = begin
        p = pair(a)
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
    flatten(@q let $args; $body end)
end
