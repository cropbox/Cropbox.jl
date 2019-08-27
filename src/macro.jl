using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S<:Union{Symbol,Nothing}}
    name::Symbol
    alias::Vector{Symbol}
    args::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::S
    type::Union{Symbol,Expr,Nothing}
    tags::Dict{Symbol,Any}
    line::Union{Expr,Symbol}
end

import Base: show
show(io::IO, s::VarInfo) = begin
    println(io, "name: $(s.name)")
    println(io, "alias: $(s.alias)")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "state: $(repr(s.state))")
    println(io, "type: $(repr(s.type))")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
    println(io, "line: $(s.line)")
end

VarInfo(line::Union{Expr,Symbol}) = begin
    # name[(args..)][: alias | [alias...]] [=> body] ~ [state][::type][(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, state_::type_(tags__) | ::type_(tags__) | state_(tags__) | state_::type_ | ::type_ | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: [alias__]) | (def2_: alias__) | def2_)
    @capture(def2, name_(args__) | name_)
    args = isnothing(args) ? [] : args
    alias = isnothing(alias) ? [] : alias
    state = isnothing(state) ? nothing : Symbol(uppercasefirst(string(state)))
    type = @capture(type, [elemtype_]) ? :(Vector{$elemtype}) : type
    tags = parsetags(tags, type)
    VarInfo{typeof(state)}(name, alias, args, body, state, type, tags, line)
end

parsetags(::Nothing, type) = parsetags([], type)
parsetags(tags::Vector, type) = begin
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
    !isnothing(type) && (d[:_type] = type)
    d
end

const self = :($(esc(:self)))
const C = :($(esc(:Cropbox)))

genfield(i::VarInfo{Symbol}) = genfield(:($C.Var{$C.$(i.state)}), i.name, i.alias)
genfield(i::VarInfo{Nothing}) = genfield(esc(i.type), i.name, i.alias)
genfield(S, var, alias) = @q begin
    $var::$S
    $(@q begin $([:($a::$S) for a in alias]...) end)
end

equation(f) = begin
    fdef = splitdef(f)
    name = Meta.quot(fdef[:name])
    key(x::Symbol) = x
    key(x::Expr) = x.args[1]
    args = key.(fdef[:args]) |> Tuple{Vararg{Symbol}}
    kwargs = key.(fdef[:kwargs]) |> Tuple{Vararg{Symbol}}
    pair(x::Symbol) = nothing
    pair(x::Expr) = x.args[1] => x.args[2]
    default = filter(!isnothing, [pair.(fdef[:args]); pair.(fdef[:kwargs])]) |> Dict{Symbol,Any}
    func = @q function $(esc(gensym(fdef[:name])))($(esc.(fdef[:args])...); $(esc.(fdef[:kwargs])...)) $(esc(fdef[:body])) end
    :($C.Equation($func, $name, $args, $kwargs, $default))
end

macro equation(f)
    e = equation(f)
    #FIXME: redundant call of splitdef() in equation()
    name = splitdef(f)[:name]
    :($(esc(name)) = $e)
end

genoverride(name, default) = @q get(_kwargs, $(Meta.quot(name)), $default)

gendecl(i::VarInfo{Symbol}) = begin
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
            e = equation(f)
        else
            @error "Function not provided: $(i.name)"
        end
    else
        f = @q function $(i.name)($(Tuple(i.args)...)) $(i.body) end
        e = equation(f)
    end
    name = Meta.quot(i.name)
    alias = Tuple(i.alias)
    value = haskey(i.tags, :override) ? genoverride(i.name, missing) : missing
    stargs = [:($(esc(k))=$(esc(v))) for (k, v) in i.tags]
    decl = :($C.Var($self, $e, $C.$(i.state); _name=$name, _alias=$alias, _value=$value, $(stargs...)))
    gendecl(decl, i.name, i.alias)
end
gendecl(i::VarInfo{Nothing}) = begin
    @assert isempty(i.args) "Non-Var `$(i.name)` cannot have arguments: $(i.args)"
    if haskey(i.tags, :override)
        decl = genoverride(i.name, esc(i.body))
    elseif !isnothing(i.body)
        decl = esc(i.body)
    else
        decl = :($(esc(i.type))())
    end
    if haskey(i.tags, :expose)
        decl = :($(esc(i.name)) = $decl)
    end
    gendecl(decl, i.name, i.alias)
end
gendecl(decl, var, alias) = @q begin
    $self.$var = $decl
    $(@q begin $([:($self.$a = $self.$var) for a in alias]...) end)
end

gensource(infos) = begin
    l = [i.line for i in infos]
    striplines(flatten(@q begin $(l...) end))
end

genfieldnamesunique(infos) = Tuple(i.name for i in infos)

genstruct(name, infos, incl) = begin
    S = esc(name)
    fields = genfield.(infos)
    decls = gendecl.(infos)
    source = gensource(infos)
    system = @q begin
        mutable struct $name <: $C.System
            $(fields...)
            function $name(; _kwargs...)
                $self = new()
                $(decls...)
                $self
            end
        end
        $C.source(::Val{Symbol($S)}) = $(Meta.quot(source))
        $C.mixins(::Type{$S}) = Tuple($(esc(:eval)).($incl))
        $C.fieldnamesunique(::Type{$S}) = $(genfieldnamesunique(infos))
        @generated $C.collectible(::Type{$S}) = $C.filtervar(Union{$C.System, Vector{$C.System}, $C.Var{$C.Produce}}, $S)
        @generated $C.updatable(::Type{$S}) = $C.filtervar($C.Var, $S)
        $S
    end
    flatten(system)
end

#TODO: maybe need to prevent naming clash by assigning UUID for each System
source(s::System) = source(typeof(s))
source(S::Type{<:System}) = source(Symbol(S))
source(s::Symbol) = source(Val(s))
source(::Val{:System}) = @q begin
    self => self ~ ::Cropbox.System
    context ~ ::Cropbox.Context(override, expose)
end
mixins(::Type{<:System}) = [System]
mixins(s::System) = mixins(typeof(s))

fieldnamesunique(::Type{<:System}) = ()
filtervar(type::Type, ::Type{S}) where {S<:System} = begin
    d = collect(zip(fieldnames(S), fieldtypes(S)))
    F = fieldnamesunique(S)
    filter!(p -> p[1] in F, d)
    filter!(p -> p[2] <: type, d)
    map(p -> p[1], d) |> Tuple{Vararg{Symbol}}
end
@generated collectible(::Type{S}) where {S<:System} = filtervar(Union{System, Vector{System}, Var{Produce}}, S)
@generated updatable(::Type{S}) where {S<:System} = filtervar(Var, S)

parsehead(head) = begin
    @capture(head, name_(mixins__) | name_)
    mixins = isnothing(mixins) ? [] : mixins
    incl = [:System]
    for m in mixins
        push!(incl, m)
    end
    (name, incl)
end

import DataStructures: OrderedDict
gensystem(head, body) = gensystem(parsehead(head)..., body)
gensystem(name, incl, body) = begin
    con(b) = OrderedDict(i.name => i for i in VarInfo.(striplines(b).args))
    add!(d, b) = merge!(d, con(b))
    d = OrderedDict{Symbol,VarInfo}()
    for m in incl
        add!(d, source(m))
    end
    add!(d, body)
    infos = collect(values(d))
    genstruct(name, infos, incl)
end

macro system(head, body)
    gensystem(head, body)
end

export @equation, @system
