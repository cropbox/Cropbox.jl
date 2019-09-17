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
        #FIXME: lower duplicate efforts in genvartype()
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

genvartype(i::VarInfo) = genvartype(i)

genvartype(i::VarInfo{Nothing}) = esc(i.type)
genvartype(i::VarInfo{Symbol}) = begin
    N = isnothing(i.type) ? :Float64 : esc(i.type)
    U = get(i.tags, :unit, nothing)
    V = @q $C.valuetype($N, $U)
    genvartype(i, Val(i.state); N=N, U=U, V=V)
end
genvartype(i::VarInfo, ::Val{:Hold}; _...) = @q Hold{Any}
genvartype(i::VarInfo, ::Val{:Advance}; V, _...) = @q Advance{$V}
genvartype(i::VarInfo, ::Val{:Preserve}; V, _...) = @q Preserve{$V}
genvartype(i::VarInfo, ::Val{:Track}; V, _...) = @q Track{$V}
genvartype(i::VarInfo, ::Val{:Drive}; V, _...) = @q Drive{$V}
genvartype(i::VarInfo, ::Val{:Call}; V, _...) = begin
    extract(a) = let k, t, u
        @capture(a, k_::t_(u_) | k_::t_ | k_(u_) | k_)
        t = isnothing(t) ? :Float64 : esc(t)
        @q $C.valuetype($t, $u)
    end
    F = @q FunctionWrapper{$V, Tuple{$(extract.(i.kwargs)...)}}
    @q Call{$V,$F}
end
genvartype(i::VarInfo, ::Val{:Accumulate}; N, U, V, _...) = begin
    #TODO: automatic inference without explicit `timeunit` tag
    TU = get(i.tags, :timeunit, nothing)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Accumulate{$V,$T,$R}
end
genvartype(i::VarInfo, ::Val{:Capture}; N, U, V, _...) = begin
    TU = get(i.tags, :timeunit, nothing)
    TU = isnothing(TU) ? @q(u"hr") : TU
    T = @q $C.valuetype(Float64, $TU)
    RU = @q $C.rateunittype($U, $TU)
    R = @q $C.valuetype($N, $RU)
    @q Capture{$V,$T,$R}
end
genvartype(i::VarInfo, ::Val{:Flag}; _...) = @q Flag{Bool}
genvartype(i::VarInfo, ::Val{:Produce}; _...) = begin
    S = isnothing(i.type) ? :System : esc(i.type)
    @q Produce{$S}
end
genvartype(i::VarInfo, ::Val{:Solve}; V, _...) = @q Solve{$V}

posedvars(infos) = names.(infos) |> Iterators.flatten |> collect

gencall(i::VarInfo) = gencall(i, Val(i.state))
gencall(i::VarInfo, ::Val) = nothing
gencall(i::VarInfo, ::Val{:Call}) = begin
    args = genfuncargs(i)
    body = flatten(@q let $args; $(i.body) end)
    @q function $(symcall(i))($(Tuple(i.kwargs)...)) $body end
end
gencalls(infos) = filter(!isnothing, gencall.(infos))

genfield(type, name, alias) = @q begin
    $name::$type
    $(@q begin $([:($a::$type) for a in alias]...) end)
end
genfield(i::VarInfo) = genfield(genvartype(i), i.name, i.alias)
genfields(infos) = [genfield(i) for i in infos]

genoverride(name, default) = @q get(_kwargs, $(Meta.quot(name)), $default)

import DataStructures: OrderedSet
gendecl(N::Vector{VarNode}) = gendecl.(OrderedSet([n.info for n in N]))
gendecl(i::VarInfo{Symbol}) = begin
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
    calls = gencalls(infos)
    fields = genfields(infos)
    decls = gendecl(nodes)
    vars = posedvars(infos)
    source = gensource(infos)
    system = @q begin
        struct $name <: $C.System
            $(fields...)
            function $name(; _kwargs...)
                _names = $C.names.([$C.mixins($name)..., $name]) |> Iterators.flatten |> collect
                $(decls...)
                new($(vars...))
            end
        end
        $C.source(::Val{$(Meta.quot(name))}) = $(Meta.quot(source))
        $C.mixins(::Type{<:$S}) = Tuple($(esc(:eval)).($incl))
        $C.fieldnamesunique(::Type{<:$S}) = $(genfieldnamesunique(infos))
        #HACK: redefine them to avoid world age problem
        @generated $C.collectible(::Type{<:$S}) = $C.filteredfields(Union{$C.System, Vector{$C.System}, $C.Produce{<:Any}}, $S)
        @generated $C.updatable(::Type{<:$S}) = $C.filteredvars($S)
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
mixins(::Type{<:System}) = [System]
mixins(s::S) where {S<:System} = mixins(S)

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
@generated update!(::System) = nothing

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

export @system

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
    @gensym s t f r
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s))
        $C.queue!(context.queue, () -> ($s.tick = $t; $s.rate = $r), $C.priority($C.$(v.state)))
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
    @gensym s t f r
    @q let $s = $(symstate(v)),
           $t = $C.value($(v.tags[:time])),
           $f = $(genfunc(v)),
           $r = $C.unitfy($f, $C.rateunit($s))
        $C.queue!(context.queue, () -> ($s.tick = $t; $s.rate = $r), $C.priority($C.$(v.state)))
    end
end

genupdate(v::VarInfo, ::Val{:Flag}, ::MainStep) = genvalue(v)
genupdate(v::VarInfo, ::Val{:Flag}, ::PostStep) = begin
    @gensym s f
    if get(v.tags, :oneway, false)
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v))
            if !$C.value($s)
                $C.queue!(context.queue, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
            end
        end
    else
        @q let $s = $(symstate(v)),
               $f = $(genfunc(v))
            $C.queue!(context.queue, () -> $C.store!($s, $f), $C.priority($C.$(v.state)))
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
            $C.queue!(context.queue, function ()
                for p in $P
                    append!($s.value, p.type(; context=$c, p.args...))
                end
                $C.inform!($o)
            end, $C.priority($C.$(v.state)))
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
