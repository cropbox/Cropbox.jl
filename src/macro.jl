using MacroTools
import MacroTools: @q, flatten, striplines

struct VarInfo{S<:Union{Symbol,Nothing}}
    var::Symbol
    alias::Vector{Symbol}
    args::Vector
    body#::Union{Expr,Symbol,Nothing}
    state::S
    type::Union{Symbol,Expr,Nothing}
    tags::Dict{Symbol,Any}
end

import Base: show
show(io::IO, s::VarInfo) = begin
    println(io, "var: $(s.var)")
    println(io, "alias: $(s.alias)")
    println(io, "func ($(repr(s.args))) = $(repr(s.body))")
    println(io, "state: $(s.state)")
    println(io, "type: $(repr(s.type))")
    for (k, v) in s.tags
        println(io, "tag $k = $v")
    end
end

VarInfo(line::Union{Expr,Symbol}) = begin
    # name[(args..)][: alias | [alias...]] [=> body] ~ [state][::type][(tags..)]
    @capture(line, decl_ ~ deco_)
    @capture(deco, state_::type_(tags__) | ::type_(tags__) | state_(tags__) | state_::type_ | ::type_ | state_)
    @capture(decl, (def1_ => body_) | def1_)
    @capture(def1, (def2_: [alias__]) | (def2_: alias_) | def2_)
    @capture(def2, name_(args__) | name_)
    args = isnothing(args) ? [] : args
    alias = isnothing(alias) ? [] : alias
    state = isnothing(state) ? nothing : Symbol(uppercasefirst(string(state)))
    type = @capture(type, [elemtype_]) ? :(Vector{$elemtype}) : type
    tags = parsetags(tags, type)
    VarInfo{typeof(state)}(name, alias, args, body, state, type, tags)
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

genfield(i::VarInfo{Symbol}) = genfield(:($(esc(:Cropbox)).Var{$(esc(:Cropbox)).$(i.state)}), i.var, i.alias)
genfield(i::VarInfo{Nothing}) = genfield(esc(i.type), i.var, i.alias)
genfield(S, var, alias) = @q begin
    $var::$S
    $(@q begin $([:($a::$S) for a in alias]...) end)
end

equation(f) = begin
    fdef = splitdef(f)
    name = Meta.quot(fdef[:name])
    key(x::Symbol) = x
    key(x::Expr) = x.args[1]
    args = key.(fdef[:args])
    kwargs = key.(fdef[:kwargs])
    pair(x::Symbol) = nothing
    pair(x::Expr) = x.args[1] => x.args[2]
    default = filter(!isnothing, [pair.(fdef[:args]); pair.(fdef[:kwargs])]) |> Dict
    func = @q function $(gensym())($(esc.(fdef[:args])...); $(esc.(fdef[:kwargs])...)) $(esc(fdef[:body])) end
    :($(esc(:Cropbox)).Equation($func, $name, $args, $kwargs, $default))
end

macro equation(f)
    e = equation(f)
    #FIXME: redundant call of splitdef() in equation()
    name = splitdef(f)[:name]
    :($(esc(name)) = $e)
end

gendecl(i::VarInfo{Symbol}) = begin
    if isnothing(i.body)
        @assert isempty(i.args)
        e = esc(i.var)
    else
        f = @q function $(i.var)($(Tuple(i.args)...)) $(i.body) end
        e = equation(f)
    end
    name = Meta.quot(i.var)
    stargs = [:($(esc(k))=$(esc(v))) for (k, v) in i.tags]
    decl = :($(esc(:Cropbox)).Var($self, $e, $(esc(:Cropbox)).$(i.state); _name=$name, _alias=$(i.alias), $(stargs...)))
    gendecl(decl, i.var, i.alias)
end
gendecl(i::VarInfo{Nothing}) = begin
    if haskey(i.tags, :override)
        k = Meta.quot(i.var)
        decl = @q $(esc(:Base)).haskey(_kwargs, $k) ? _kwargs[$k] : $(esc(i.body))
    elseif !isnothing(i.body)
        # @assert isnothing(i.args)
        decl = esc(i.body)
    else
        decl = :($(esc(i.type))())
    end
    if haskey(i.tags, :expose)
        decl = :($(esc(i.var)) = $decl)
    end
    gendecl(decl, i.var, i.alias)
end
gendecl(decl, var, alias) = @q begin
    $self.$var = $decl
    $(@q begin $([:($self.$a = $self.$var) for a in alias]...) end)
end

genstruct(name, infos, body, options) = begin
    fields = genfield.(infos)
    decls = gendecl.(infos)
    source = striplines(body)
    system = @q begin
        mutable struct $name <: $(esc(:Cropbox)).System
            $(fields...)
            function $name(; _kwargs...)
                $self = new()
                $(decls...)
                $self
            end
        end
        $(esc(:Cropbox)).source(::$(esc(:Val)){$(esc(:Symbol))($(esc(name)))}) = $(Meta.quot(source))
        $(esc(:Cropbox)).sourceopt(::$(esc(:Val)){$(esc(:Symbol))($(esc(name)))}) = $options
        $(esc(name))
    end
    flatten(system)
end

#TODO: maybe need to prevent naming clash by assigning UUID for each System
source(s::Symbol) = source(Val(s))
source(::Val{:System}) = @q begin
    self => self ~ ::Cropbox.System
    context ~ ::Cropbox.Context(override, expose)
end
sourceopt(s::Symbol) = sourceopt(Val(s))
sourceopt(::Val{:System}) = []

gensystem(name, body) = gensystem(name, body, [])
gensystem(name, body, option::Symbol) = gensystem(name, body, [option])
gensystem(name, body, options::Expr) = begin
    if isexpr(options, :tuple)
        gensystem(name, body, options.args)
    else
        gensystem(name, body, [options])
    end
end
gensystem(name, body, options::Vector) = begin
    b = []
    if :bare ∉ options
        push!(b, source(:System))
    end
    for o in options
        if @capture(o, include(names__))
            for n in names
                push!(b, source(n))
            end
        end
    end
    push!(b, body)
    block = striplines(flatten(@q begin $(b...) end))
    infos = [VarInfo(line) for line in block.args] |> dedup
    genstruct(name, infos, body, options)
end

using DataStructures
dedup(infos) = OrderedDict(i.var => i for i in infos) |> values |> collect

macro system(name, body)
    gensystem(name, body)
end
macro system(name, options, body)
    gensystem(name, body, options)
end

export @equation, @system
