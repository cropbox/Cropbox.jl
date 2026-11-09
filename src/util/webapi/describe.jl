# Model introspection shared by the web API.
#
# `variables()` collects variable metadata once for a system tree and is the
# single source for `describe()`; other tools (dashboards, documentation,
# sensitivity analysis) can reuse it instead of walking `dependency()` again.

import DataAPI: describe

"Variable states whose values are meaningful simulation outputs."
const OUTPUT_STATES = (:Track, :Accumulate, :Capture, :Drive, :Preserve, :Flag, :Bisect, :Solve)

"DSL tags published to clients; the remaining tags are implementation details."
const PUBLIC_TAGS = Set((
    :by, :from, :lower, :max, :maxiter, :min, :optional, :pick,
    :round, :roundunit, :to, :tol, :upper, :when,
))

"""
    variables(S::Type{<:System}; recursive=true, exclude=(Context,))

Collect metadata for every variable declared in `S` and, when `recursive` is
set, in its subsystems. Returns a vector of named tuples with fields:

- `system`: name of the system owning the variable
- `path`: access path of that system from the root (empty for the root)
- `name`, `alias`, `state`, `type`, `unit`, `description`
- `target`: access path used as a simulation target (`"leaf.area"`)
- `config`: configuration path (`"Leaf.area"`) and `declared`, the same path
  through the system that declared the variable (differs for mixins)
- `role`: `"parameter"`, `"table"` (a `provide` input), `"output"` or `"internal"`
- `tags`: public DSL tags, `dependencies`: names of variables it reads
- `info`: the underlying `VarInfo`

Systems listed in `exclude` (and their subtrees) are skipped.
"""
variables(S::Type{<:System}; recursive=true, exclude=(Context,)) = begin
    V = NamedTuple[]
    for (T, path, _) in systemtree(S; recursive, exclude)
        system = namefor(T)
        units = fieldunits(T)
        for v in geninfos(T)
            isnothing(v.state) && continue
            name = v.name
            push!(V, (;
                system,
                path,
                name,
                alias = v.alias,
                state = v.state,
                type = typelabel(gettag(v, :_type, nothing)),
                unit = get(units, name, nothing),
                description = strip(v.docstring),
                target = isempty(path) ? string(name) : "$(path).$(name)",
                config = "$(system).$(uncanonicalname(name, system))",
                declared = "$(v.system).$(uncanonicalname(name, v.system))",
                role = variablerole(v),
                tags = publictags(v),
                dependencies = sort!(string.(uncanonicalname.(collect(extract(v; tag=false))))),
                info = v,
            ))
        end
    end
    V
end

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

# Tag expressions are quoted by the `@system` macro; evaluate the simple ones and
# fall back to their source text.
tagvalue(raw::QuoteNode) = tagvalue(raw.value)
tagvalue(raw::Symbol) = string(uncanonicalname(raw))
tagvalue(raw::Union{Number,Bool,AbstractString}) = encode(raw)
tagvalue(raw::Nothing) = nothing
tagvalue(raw::AbstractVector) = tagvalue.(raw)
tagvalue(raw) = begin
    v = try value(raw) catch; raw end
    v === raw ? string(raw) : tagvalue(v)
end

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
systems, parameters (with defaults under `config`), output variables and
provided-table bindings. It is served at `GET /api/model` by [`serve`](@ref) and
can be used directly by other tools.
"""
describe(S::Type{<:System}; config=(), recursive=true, exclude=(Context,)) = begin
    V = variables(S; recursive, exclude)
    byname = Dict((v.system, v.name) => v for v in V)
    for v in V
        isnothing(v.alias) || (byname[(v.system, v.alias)] = v)
    end
    defaults = parameterflatten(configure(parameters(S; recursive, exclude), config))
    units = parameterunits(collect(keys(defaults)))
    parameters_ = [
        let v = get(byname, (system, name), nothing),
            unit = isnothing(v) || isnothing(v.unit) ? (ismissing(u) ? nothing : u) : v.unit
            entry = isnothing(v) ? APIDict(
                "system" => string(system), "name" => string(name), "alias" => nothing,
                "path" => "$(system).$(name)", "declared" => "$(system).$(name)", "target" => string(name),
                "description" => "", "state" => nothing, "type" => nothing, "unit" => unitlabel(unit),
                "role" => "parameter", "tags" => APIDict(), "dependencies" => String[],
            ) : variableentry(v)
            entry["unit"] = unitlabel(unit)
            entry["default"] = entry["role"] == "table" ? nothing : encodevalue(value, unit)
            entry
        end
        for (((system, name), value), u) in zip(defaults, units)
    ]
    APIDict(
        "contract" => APIDict("version" => API_CONTRACT_VERSION),
        "model" => APIDict("name" => string(nameof(S)), "module" => string(parentmodule(S))),
        "systems" => systementries(S; recursive, exclude),
        "parameters" => parameters_,
        "variables" => [variableentry(v) for v in V if v.role in ("output", "internal")],
        "tables" => [tableentry(v, V) for v in V if v.role == "table"],
    )
end

variableentry(v) = APIDict(
    "system" => string(v.system),
    "name" => string(v.name),
    "alias" => isnothing(v.alias) ? nothing : string(v.alias),
    "path" => v.config,
    "declared" => v.declared,
    "target" => v.target,
    "description" => String(v.description),
    "state" => lowercase(string(v.state)),
    "type" => v.type,
    "unit" => unitlabel(v.unit),
    "role" => v.role,
    "tags" => v.tags,
    "dependencies" => v.dependencies,
)

# A `provide` table and the `drive` variables reading its columns.
tableentry(t, V) = begin
    entry = variableentry(t)
    entry["index"] = tagvalue(gettag(t.info, :index, QuoteNode(:index)))
    entry["columns"] = [
        APIDict(
            "variable" => d.target,
            "name" => string(d.name),
            "column" => tagvalue(gettag(d.info, :by, QuoteNode(d.name))),
            "unit" => unitlabel(d.unit),
        )
        for d in V
        if d.state == :Drive && d.system == t.system && d.path == t.path && tagsymbol(gettag(d.info, :from, nothing)) == t.name
    ]
    entry
end

tagsymbol(raw::QuoteNode) = tagsymbol(raw.value)
tagsymbol(raw::Symbol) = raw
tagsymbol(raw) = nothing

"System types reachable from `S` as `(type, access path, root)` tuples, skipping `exclude`d systems."
systemtree(S::Type{<:System}; recursive=true, exclude=(Context,)) = begin
    seen = Set{Any}()
    tree = Tuple{Any,String,Bool}[]
    visit!(T, path, root) = begin
        any(E -> T <: E, exclude) && return
        key = (typefor(T), path)
        key in seen && return
        push!(seen, key)
        push!(tree, (T, path, root))
        recursive || return
        for f in subsystemsof(T)
            C = fieldtype(typefor(T), f)
            C <: System && visit!(C, isempty(path) ? string(f) : "$(path).$(f)", false)
        end
    end
    visit!(S, "", true)
    tree
end

systementries(S::Type{<:System}; recursive=true, exclude=(Context,)) = [
    APIDict("name" => string(namefor(T)), "module" => string(parentmodule(T)), "root" => root, "path" => path)
    for (T, path, root) in systemtree(S; recursive, exclude)
]

"""
    parametertypes(description) -> Dict{String,Tuple}

Map every configuration path accepted by a described model (`path` and
`declared`) to its declared `(type, unit, role)`. Used to coerce and validate
client-supplied configuration values.
"""
parametertypes(description::APIDict) = begin
    types = Dict{String,Tuple{Any,Any,String}}()
    for p in description["parameters"]
        for path in unique((p["path"], p["declared"]))
            types[path] = (p["type"], p["unit"], p["role"])
        end
    end
    for t in description["tables"]
        for path in unique((t["path"], t["declared"]))
            types[path] = (nothing, nothing, "table")
        end
    end
    types
end

"Target paths that requests may reference as `target`, `index`, `stop`, `x` or `y`."
targetpaths(description::APIDict) = begin
    paths = Set{String}(("time",))
    for group in ("parameters", "variables", "tables"), v in description[group]
        push!(paths, v["target"])
        isnothing(v["alias"]) || push!(paths, replace(v["target"], r"[^.]+$" => v["alias"]))
    end
    paths
end
