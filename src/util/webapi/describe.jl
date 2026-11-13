# Model introspection shared by the web API.
#
# `variables()` collects variable metadata once for a system tree. It is the
# single source for `describe()` and for the index that validates requests;
# other tools (dashboards, documentation, sensitivity analysis) can reuse it
# instead of walking `dependency()` again.

import DataAPI: describe

"Variable states whose values are meaningful simulation outputs."
const OUTPUT_STATES = (:Track, :Accumulate, :Capture, :Integrate, :Advance, :Remember, :Drive, :Preserve, :Flag, :Bisect, :Solve)

"DSL tags published to clients; the remaining tags are implementation details."
const PUBLIC_TAGS = Set((
    :by, :from, :lower, :max, :maxiter, :min, :optional, :pick,
    :round, :roundunit, :to, :tol, :upper, :when,
))

"""
    variables(S::Type{<:System}; recursive=true, exclude=(Context,))

Collect metadata for every variable declared in `S` and, when `recursive` is
set, in the systems below it. Returns a vector of named tuples with fields:

- `system`: name of the system owning the variable
- `path`: access path of that system from the root (empty for the root,
  `nothing` for a system that only exists once the model `produce`s it)
- `name`, `alias`, `state`, `type`, `unit`, `description`
- `target`: access path used as a simulation target (`"leaf.area"`), or
  `nothing` without a fixed path
- `config`: configuration path (`"Leaf.area"`) and `declared`, the same path
  through the system that declared the variable (differs for mixins)
- `systems`: the system names under which Cropbox looks the variable up in a
  configuration, in order of precedence (the system, then its mixins)
- `role`: `"parameter"`, `"table"` (a `provide` input), `"output"` or `"internal"`
- `tags`: public DSL tags, `dependencies`: names of variables it reads
- `excluded`: whether the system is one of `exclude` or below one. These (by
  default the context with its clock) are left out of a description but are
  configured and read like any other system
- `info`: the underlying `VarInfo`

A system reached through several paths is listed once per path.
"""
variables(S::Type{<:System}; recursive=true, exclude=(Context,)) = variables(systemtree(S; recursive, exclude))
variables(tree::AbstractVector) = begin
    V = NamedTuple[]
    bytype = Dict{Any,Any}()
    for t in tree
        # what a system type declares is the same on every path to it
        D = get!(bytype, typefor(t.system)) do
            system = namefor(t.system)
            units = fieldunits(t.system)
            systems = systemkeys(t.system)
            [(;
                system,
                name = v.name,
                alias = v.alias,
                state = v.state,
                type = typelabel(gettag(v, :_type, nothing)),
                unit = get(units, v.name, nothing),
                description = strip(v.docstring),
                config = "$(system).$(uncanonicalname(v.name, system))",
                declared = "$(v.system).$(uncanonicalname(v.name, v.system))",
                systems,
                role = variablerole(v),
                tags = publictags(v),
                dependencies = sort!(string.(uncanonicalname.(collect(extract(v; tag=false))))),
                info = v,
            ) for v in t.infos if !isnothing(v.state)]
        end
        path = t.path
        for d in D
            target = isnothing(path) ? nothing : isempty(path) ? string(d.name) : "$(path).$(d.name)"
            push!(V, (; d..., path, target, excluded = t.excluded))
        end
    end
    V
end

"""
System types below `S` as `(system, path, root, excluded, infos)` named tuples:
first, depth first, the systems held in statically typed fields with their
access `path`; then the types the model only `produce`s while it runs, once
each and without a path (`nothing`). `excluded` marks the systems in `exclude`
and everything below them. A type is not entered again below itself, so cyclic
references end.
"""
systemtree(S::Type{<:System}; recursive=true, exclude=(Context,)) = begin
    tree = NamedTuple[]
    infos = Dict{Any,Any}()
    produced = Tuple{Any,Bool}[]
    visit!(T, path, above, excluded) = begin
        C = typefor(T)
        # an open type (`System`, a union) is only known once the model runs
        isconcretetype(C) || return
        (C in above || (isnothing(path) && haskey(infos, C))) && return
        excluded |= any(E -> T <: E, exclude)
        I = get!(() -> geninfos(T), infos, C)
        push!(tree, (; system=T, path, root=path == "", excluded, infos=I))
        recursive || return
        for f in subsystemsof(T)
            visit!(fieldtype(C, f), isnothing(path) ? nothing : isempty(path) ? string(f) : "$(path).$(f)", (above..., C), excluded)
        end
        for v in I
            v.state == :Produce || continue
            for P in producedtypes(T, v)
                push!(produced, (P, excluded))
            end
        end
    end
    visit!(S, "", (), false)
    while !isempty(produced)
        T, excluded = popfirst!(produced)
        visit!(T, nothing, (), excluded)
    end
    tree
end

"""
System types that a `produce` variable of `T` creates: the type it declares when
that is one system, and otherwise the systems that its body passes to `produce`
(`produce(Child; config)`) among those of the declared kind (`produce::Family[]`,
or any system without a declaration). Empty when neither names one, as for a type
computed while the model runs.
"""
producedtypes(T, v::VarInfo) = begin
    resolve(x) = try
        P = Core.eval(scopeof(T), x)
        P isa Type && P <: AbstractVector && (P = eltype(P))
        P isa Type && P <: System ? P : nothing
    catch
        nothing
    end
    declared = something(resolve(v.type), System)
    isconcretetype(typefor(declared)) && return [declared]
    found = []
    walk(x) = nothing
    walk(x::Expr) = begin
        if x.head == :call && !isempty(x.args) && x.args[1] in (:produce, :(Cropbox.produce))
            # keyword arguments come first in the call when they follow a semicolon
            A = filter(a -> !(a isa Expr && a.head in (:parameters, :kw)), x.args[2:end])
            # a name only: what a call would compute is only known once the model runs
            isempty(A) || !(first(A) isa Symbol || Meta.isexpr(first(A), :.)) || push!(found, resolve(first(A)))
        end
        foreach(walk, x.args)
    end
    walk(v.body)
    unique(P for P in found if !isnothing(P) && P <: declared && isconcretetype(typefor(P)))
end

"`produce` variables of the tree whose systems `producedtypes` cannot name, as `System.name` paths."
openproduce(tree) = unique(["$(namefor(t.system)).$(v.name)" for t in tree for v in t.infos if v.state == :Produce && isempty(producedtypes(t.system, v))])

"System names under which Cropbox looks up the parameters of `T`, in its order of precedence: the system, then its mixins."
systemkeys(T) = collect(Symbol, Iterators.flatten(reverse(names.(collect(mixincollect(supertype(typefor(T))))))))

"Names under which a variable is configured: its name and its alias."
namekeys(v) = isnothing(v.alias) ? [v.name] : [v.name, v.alias]

"Every `(system, name)` configuration key Cropbox reads for a parameter, in its order of precedence."
spellings(v) = [(s, uncanonicalname(k, shortname(s))) for k in namekeys(v) for s in v.systems]

"The name of a system without its modules: `Leaf` for `Main.Plant.Leaf`."
shortname(s) = Symbol(last(split(string(s), '.')))

variablerole(v::VarInfo) = begin
    v.state == :Provide && return "table"
    istag(v, :parameter) && return "parameter"
    v.state in OUTPUT_STATES ? "output" : "internal"
end

publictags(v::VarInfo) = begin
    tags = APIDict()
    for (tag, raw) in v.tags
        tag in PUBLIC_TAGS || continue
        encoded = tagvalue(raw)
        tag == :optional && encoded === false && continue
        tags[string(tag)] = encoded
    end
    tags
end

# Tag expressions are quoted by the `@system` macro: literals keep their value, anything else is source text.
tagvalue(raw::QuoteNode) = tagvalue(raw.value)
tagvalue(raw::Symbol) = string(uncanonicalname(raw))
tagvalue(raw::Union{Number,Bool,AbstractString}) = encode(raw)
tagvalue(raw::Nothing) = nothing
tagvalue(raw::AbstractVector) = tagvalue.(raw)
tagvalue(raw) = string(raw)

# Declared type expression (`_type` tag) rendered as a public type name.
typelabel(::Nothing) = nothing
typelabel(raw::QuoteNode) = typelabel(raw.value)
typelabel(raw::Expr) = begin
    raw.head in (:escape, :quote) && length(raw.args) == 1 && return typelabel(only(raw.args))
    raw.head == :. && return typelabel(last(raw.args))
    raw.head == :call && length(raw.args) == 2 && typelabel(first(raw.args)) == "typefor" && return typelabel(last(raw.args))
    raw.head == :curly && !isempty(raw.args) && return "$(typelabel(first(raw.args))){$(join(typelabel.(raw.args[2:end]), ", "))}"
    string(raw)
end
typelabel(raw) = string(raw)

"""
    describe(S::Type{<:System}; config=(), recursive=true, exclude=(Context,))

Return a JSON-compatible description of a Cropbox system: model identity,
systems, parameters (with their values under `config`), output variables and
provided-table bindings. It is served at `GET /api/model` by [`serve`](@ref) and
can be used directly by other tools.

Systems in `exclude` and below them are left out, except for their parameters
that `config` sets (such as the clock step).
"""
describe(S::Type{<:System}; config=(), recursive=true, exclude=(Context,)) = begin
    tree = systemtree(S; recursive, exclude)
    description(S, tree, variables(tree); config)
end

description(S::Type{<:System}, tree, V; config=()) = begin
    c = configure(config)
    # the defaults of each system the tree reached, rather than a second walk that would follow open types
    systems = unique(t -> typefor(t.system), [t for t in tree if !t.excluded])
    defaults = merge(Dict(), (parameterflatten(parameters(t.system)) for t in systems)...)
    P = APIDict[]
    seen = Set{Tuple{Symbol,Symbol}}()
    for v in V
        istag(v.info, :parameter) || continue
        # a system reached through several paths has one set of parameters
        (v.system, v.name) in seen && continue
        # the value Cropbox will use: `config` may set it through an alias or a mixin name
        value = option(c, v.systems, namekeys(v))
        v.excluded && ismissing(value) && continue
        push!(seen, (v.system, v.name))
        ismissing(value) && (value = get(defaults, (v.system, v.name), missing))
        e = variableentry(v)
        e["default"] = v.role == "table" ? nothing : encodedefault(value, v.unit, v.type)
        push!(P, e)
    end
    described = [v for v in V if !v.excluded]
    APIDict(
        "contract" => APIDict("version" => API_CONTRACT_VERSION),
        "model" => APIDict("name" => string(nameof(S)), "module" => string(parentmodule(S))),
        "systems" => [
            APIDict("name" => string(namefor(t.system)), "module" => string(parentmodule(t.system)), "root" => t.root, "path" => t.path)
            for t in tree if !t.excluded
        ],
        "parameters" => P,
        "variables" => [variableentry(v) for v in described if v.role in ("output", "internal") && !isnothing(v.target)],
        "tables" => [tableentry(v, described) for v in described if v.role == "table"],
    )
end

# A default that cannot be converted to the declared unit as a whole (e.g. `interpolate` knots) is encoded as it is.
encodedefault(value, unit, type) = try
    encodevalue(value, unit; type)
catch
    encodevalue(value; type)
end

"A description entry: parameters, variables, tables and the dashboard's own entries share these keys."
entry(; system, name, alias=nothing, path="$(system).$(name)", declared=path, target=string(name), description="",
        state=nothing, type=nothing, unit=nothing, role, tags=APIDict(), dependencies=String[]) = APIDict(
    "system" => string(system),
    "name" => string(name),
    "alias" => isnothing(alias) ? nothing : string(alias),
    "path" => path,
    "declared" => declared,
    "target" => target,
    "description" => String(description),
    "state" => isnothing(state) ? nothing : lowercase(string(state)),
    "type" => type,
    "unit" => unitlabel(unit),
    "role" => role,
    "tags" => tags,
    "dependencies" => dependencies,
)

variableentry(v) = entry(; v.system, v.name, v.alias, path=v.config, v.declared, v.target, v.description, v.state, v.type, v.unit, v.role, v.tags, v.dependencies)

# A `provide` table and the `drive` variables reading its columns.
tableentry(t, V) = begin
    e = variableentry(t)
    e["index"] = tagvalue(gettag(t.info, :index, QuoteNode(:index)))
    e["columns"] = [
        APIDict(
            "variable" => d.target,
            "name" => string(d.name),
            "column" => tagvalue(gettag(d.info, :by, QuoteNode(d.name))),
            "unit" => unitlabel(d.unit),
        )
        for d in V
        if d.state == :Drive && d.system == t.system && d.path == t.path && tagsymbol(gettag(d.info, :from, nothing)) == t.name
    ]
    e
end

tagsymbol(raw::QuoteNode) = tagsymbol(raw.value)
tagsymbol(raw::Symbol) = raw
tagsymbol(raw) = nothing

# --- request validation index -------------------------------------------------

"""
    ModelIndex(S)

Lookup tables for checking requests against a model, built from every system
that can be part of it (the context and produced systems included):

- `parameters`: the parameters, as entries of [`variables`](@ref), that each
  configuration path sets. Cropbox reads a parameter through its name or alias
  under its own system or any mixin of it, so several paths lead to one
  parameter, and the path of a shared mixin leads to several;
- `paths`: variable paths accepted as `target`, `index`, `stop`, `x` and `y`
  (every variable with a fixed access path, and `*` / `system.*` wildcards);
- `aliases`: access paths through an alias, each mapped to the path by name;
- `time`: the unit of the clock time, in which a `stop` or `snap` duration is read;
- `open`: the `produce` variables whose systems are only known once the model
  runs. Their parameters cannot be checked, so a request cannot set them.
"""
struct ModelIndex
    parameters::Dict{String,Vector{NamedTuple}}
    paths::Set{String}
    aliases::Dict{String,String}
    time::Units
    open::Vector{String}
end

ModelIndex(S::Type{<:System}) = (tree = systemtree(S); ModelIndex(tree, variables(tree)))
ModelIndex(tree, V) = begin
    parameters = Dict{String,Vector{NamedTuple}}()
    # a system is told apart from a namesake in another module by its most specific name, the first it answers to
    seen = Set{Tuple{Symbol,Symbol}}()
    for v in V
        istag(v.info, :parameter) || continue
        (first(v.systems), v.name) in seen && continue
        push!(seen, (first(v.systems), v.name))
        for (system, name) in spellings(v)
            push!(get!(Vector{NamedTuple}, parameters, "$(system).$(name)"), v)
        end
    end
    paths = Set{String}(("*",))
    aliases = Dict{String,String}()
    for t in tree
        isnothing(t.path) && continue
        below(name) = isempty(t.path) ? string(name) : "$(t.path).$(name)"
        push!(paths, below("*"))
        for v in t.infos
            isnothing(v.state) || push!(paths, below(v.name))
            isnothing(v.alias) || (aliases[below(v.alias)] = below(v.name))
        end
    end
    ModelIndex(parameters, paths, aliases, timeunit(clocktype(first(tree).system)), openproduce(tree))
end

"Clock type driving `S` (`Clock` unless a custom context is used)."
clocktype(S::Type{<:System}) = fieldtype(typefor(fieldtype(typefor(S), :context)), :clock)

"""
    override(base, client, index)

`client` merged over `base` so that Cropbox reads every value `client` sets for
a parameter of the model. Cropbox reads the spellings of a parameter in a fixed
order: its name before its alias, and its system by the module-qualified name
before the plain one and before a mixin. Where `base` holds a parameter under a
spelling read before the one `client` used, the client value is written once
more under the spelling read first of all. Nothing is removed, so a base setting
that the index cannot trace, such as one under a mixin name that also reaches
systems produced while the model runs, keeps its meaning.
"""
override(base, client, ::Nothing) = configure(base, client)
override(base, client, index::ModelIndex) = begin
    base, client = configure(base), configure(client)
    K = unique(v -> (first(v.systems), v.name), [v for (path, _) in flatconfig(client) for v in get(index.parameters, path, ())])
    configure(base, client, (first(v.systems) => uncanonicalname(v.name, v.system) => option(client, v.systems, namekeys(v)) for v in K if shadowed(base, client, v))...)
end

"Whether `base` holds the parameter `v` under a spelling that Cropbox reads before every one that `given` holds it under."
shadowed(base, given, v) = begin
    held(c) = findfirst(((s, k),) -> !ismissing(option(c, s, k)), spellings(v))
    i, j = held(base), held(given)
    !isnothing(i) && !isnothing(j) && i < j
end

"The system name a parameter is written under: its own, or its module-qualified one when a namesake shares that."
ownkey(v, index) = begin
    K = index.parameters["$(v.system).$(uncanonicalname(v.name, v.system))"]
    length(unique(first(u.systems) for u in K)) > 1 ? first(v.systems) : v.system
end
