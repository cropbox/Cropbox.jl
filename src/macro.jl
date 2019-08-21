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
    println(io, "state: $(s.state)")
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
    @capture(def1, (def2_: [alias__]) | (def2_: alias_) | def2_)
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

genfield(i::VarInfo{Symbol}) = genfield(:($(esc(:Cropbox)).Var{$(esc(:Cropbox)).$(i.state)}), i.name, i.alias)
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

genoverride(name, default) = begin
    k = Meta.quot(name)
    @q $(esc(:Base)).haskey(_kwargs, $k) ? _kwargs[$k] : $default
end

gendecl(i::VarInfo{Symbol}) = begin
    if isnothing(i.body)
        @assert isempty(i.args)
        e = esc(i.name)
    else
        f = @q function $(i.name)($(Tuple(i.args)...)) $(i.body) end
        e = equation(f)
    end
    name = Meta.quot(i.name)
    value = genoverride(i.name, nothing)
    stargs = [:($(esc(k))=$(esc(v))) for (k, v) in i.tags]
    decl = :($(esc(:Cropbox)).Var($self, $e, $(esc(:Cropbox)).$(i.state); _name=$name, _alias=$(i.alias), _value=$value, $(stargs...)))
    gendecl(decl, i.name, i.alias)
end
gendecl(i::VarInfo{Nothing}) = begin
    if haskey(i.tags, :override)
        decl = genoverride(i.name, esc(i.body))
    elseif !isnothing(i.body)
        # @assert isnothing(i.args)
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

genstruct(name, infos) = begin
    fields = genfield.(infos)
    decls = gendecl.(infos)
    source = gensource(infos)
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
    genstruct(name, infos)
end

macro system(head, body)
    gensystem(head, body)
end

export @equation, @system
