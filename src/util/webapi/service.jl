# HTTP service: route table, request handling, operation payloads and the
# dashboard metadata payload.

using HTTP: HTTP

const API_ROUTES = [
    (; method="GET", path="/api/model", op=:model),
    (; method="GET", path="/api/dashboard", op=:dashboard),
    (; method="GET", path="/api/schema", op=:schema),
    (; method="GET", path="/api/openapi", op=:openapi),
    (; method="GET", path="/api/docs", op=:docs),
    (; method="GET", path="/docs", op=:docs),
    (; method="POST", path="/api/simulate", op=:simulate),
    (; method="POST", path="/api/visualize", op=:visualize),
    (; method="POST", path="/api/evaluate", op=:evaluate),
    (; method="POST", path="/api/calibrate", op=:calibrate),
]

const JSON_TYPE = "application/json; charset=utf-8"
const HTML_TYPE = "text/html; charset=utf-8"

asset(name) = read(joinpath(@__DIR__, name), String)

# --- dashboard frontends ------------------------------------------------------

abstract type DashboardFrontend end
struct NoDashboard <: DashboardFrontend end
struct StaticDashboard <: DashboardFrontend
    paths::Vector{String}
end
StaticDashboard(; path=nothing, paths=nothing) = begin
    P = !isnothing(paths) ? String.(paths) : isnothing(path) ? ["/", "/dashboard"] : [String(path)]
    isempty(P) && error("dashboard paths must not be empty")
    all(startswith("/"), P) || error("dashboard paths must start with /")
    StaticDashboard(unique(P))
end

dashboardfrontend(f::DashboardFrontend) = f
dashboardfrontend(::Nothing) = NoDashboard()
dashboardfrontend(f::Bool) = f ? StaticDashboard() : NoDashboard()
dashboardfrontend(f::Symbol) = f == :static ? StaticDashboard() : f == :none ? NoDashboard() :
    error("unsupported dashboard frontend: $f. Use :static, :none, false, or a DashboardFrontend object.")
dashboardfrontend(path::AbstractString) = StaticDashboard(; path)

"Routes served by a frontend; a custom frontend overrides this and `dashboardresponse`."
dashboardroutes(::DashboardFrontend) = ["/dashboard"]
dashboardroutes(::NoDashboard) = String[]
dashboardroutes(f::StaticDashboard) = f.paths
dashboardresponse(f::DashboardFrontend, ::Type{<:System}) = error("dashboard frontend $(typeof(f)) must implement Cropbox.dashboardresponse")
dashboardresponse(::StaticDashboard, ::Type{<:System}) = (200, HTML_TYPE, asset("dashboard.html"))

# --- service ------------------------------------------------------------------

"""
    Service(S; config=(), options=(), request_defaults=(), ui=(), dashboard=:static)

A configured web service for system `S`: the model description, type and path
indexes used to validate requests, and precomputed `GET` responses. Use
`respond` to handle a request without an HTTP server.
"""
struct Service
    system::Type
    config::Config
    options::NamedTuple
    defaults::APIDict
    ui::APIDict
    frontend::DashboardFrontend
    description::APIDict
    types::Dict{String,Tuple{Any,Any,String}}
    paths::Set{String}
    cache::Dict{String,Tuple{Int,String,String}}
end

Service(S::Type{<:System}; config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static) = begin
    c = configure(config)
    o = decodeoptions(options)
    u = stringkeys(ui)
    frontend = dashboardfrontend(dashboard)
    description = describe(S; config=c)
    json(x) = (200, JSON_TYPE, JSON.json(x))
    cache = Dict{String,Tuple{Int,String,String}}(
        "/api/model" => json(description),
        "/api/dashboard" => json(widgetpayload(S; config=c, ui=u, description)),
        "/api/schema" => json(apischema()),
        "/api/openapi" => (200, JSON_TYPE, asset("openapi.json")),
        "/api/docs" => (200, HTML_TYPE, asset("swagger.html")),
        "/docs" => (200, HTML_TYPE, asset("swagger.html")),
    )
    for p in dashboardroutes(frontend)
        cache[p] = dashboardresponse(frontend, S)
    end
    Service(S, c, o, stringkeys(request_defaults), u, frontend, description, parametertypes(description), targetpaths(description), cache)
end

"""
    respond(service, method, target, body="") -> (status, content_type, body)

Handle one HTTP request against a `Service`. `GET` routes come from the
precomputed cache; `POST` routes parse the JSON body, apply `request_defaults`
and run the operation. Errors are reported as JSON with HTTP status 400
(malformed JSON), 404/405 (routing), 422 (validation) or 500 (execution).
"""
respond(s::Service, method::AbstractString, target::AbstractString, body::AbstractString="") = begin
    path = try
        HTTP.URI(target).path
    catch
        target
    end
    try
        route = findfirst(r -> r.path == path, API_ROUTES)
        if haskey(s.cache, path)
            method == "GET" || apierror("Method $method is not allowed for $path", "method")
            return s.cache[path]
        end
        isnothing(route) && apierror("No route for $path", "routing")
        method == "POST" || apierror("Method $method is not allowed for $path", "method")
        op = API_ROUTES[route].op
        request = applydefaults(s, parserequest(body), op)
        payload = operate(s, op, request)
        return (200, JSON_TYPE, JSON.json(payload))
    catch e
        return errorresponse(e; path)
    end
end

operate(s::Service, op::Symbol, r::APIDict) = begin
    kw = (; config=s.config, options=s.options, paths=s.paths)
    op == :simulate && return simulate_payload(s.system, r; kw...)
    op == :visualize && return visualize_payload(s.system, r; kw...)
    op == :evaluate && return evaluate_payload(s.system, r; kw...)
    op == :calibrate && return calibrate_payload(s.system, r; kw...)
    apierror("No route for $op", "routing")
end

parserequest(body::AbstractString) = begin
    isempty(strip(body)) && return APIDict()
    parsed = try
        JSON.parse(body, Dict{String,Any})
    catch e
        apierror("Malformed JSON body: $(sprint(showerror, e))", "syntax")
    end
    parsed isa AbstractDict || apierror("Request body must be a JSON object", "syntax")
    stringkeys(parsed)
end

"""
Merge trusted server-side `request_defaults` into a client request. Client keys
win; configurations are merged per parameter path with `configure` so a
client value replaces the corresponding default while other defaults remain.
`snap` defaults are not applied to `evaluate`/`calibrate`, which align
observations themselves.
"""
applydefaults(s::Service, request::APIDict, op::Symbol) = begin
    d = copy(s.defaults)
    op in (:evaluate, :calibrate) && delete!(d, "snap")
    merged = merge(d, request)
    client = haskey(request, "config") ? coerceconfig(s, decodeconfig(request["config"])) : nothing
    default = haskey(d, "config") ? decodeconfig(d["config"]) : nothing
    if !isnothing(client) || !isnothing(default)
        merged["config"] = configure(default, client)
    end
    merged
end

"""
Check client configuration values against the model description: table inputs
must be CSV/DataFrame payloads, string values are coerced to the declared
parameter type, and unknown parameters of a described system are rejected.
"""
coerceconfig(s::Service, c::Config) = begin
    systems = Set{String}(String(e["name"]) for e in s.description["systems"])
    P = Pair[]
    for (path, value) in flatconfig(c)
        system = String(first(split(path, ".")))
        if haskey(s.types, path)
            type, unit, role = s.types[path]
            if role == "table"
                value isa DataFrame || apierror("Table parameter `$path` requires a CSV or DataFrame payload")
            elseif value isa AbstractString && !isnothing(type) && haskey(API_TYPES, type) && !(type in ("String", "Symbol"))
                value = decodetyped(value, type)
            end
        elseif system in systems
            apierror("Unknown parameter `$path`")
        end
        push!(P, path => value)
    end
    isempty(P) ? configure() : configure(P...)
end

errorresponse(e::APIRequestError; path=nothing) = begin
    status = e.category == "syntax" ? 400 : e.category == "validation" ? 422 : e.category == "routing" ? 404 : e.category == "method" ? 405 : 500
    code = status == 404 ? "not_found" : status == 405 ? "method_not_allowed" : status == 500 ? "execution_failed" : "invalid_request"
    status, JSON_TYPE, JSON.json(errorpayload(code, e.category, e.message; path))
end
errorresponse(e; path=nothing) = 500, JSON_TYPE, JSON.json(errorpayload("execution_failed", "execution", sprint(showerror, e); path))

errorpayload(code, category, message; path=nothing) = begin
    error = APIDict("code" => code, "category" => category, "message" => message, "retryable" => false)
    isnothing(path) || (error["path"] = path)
    APIDict("status" => "error", "contract_version" => API_CONTRACT_VERSION, "error" => error)
end

# --- requests -----------------------------------------------------------------

const SIMULATION_KEYS = ("config", "configs", "index", "target", "meta", "base", "stop", "snap", "seed", "nounit", "long", "options")
const EVALUATION_KEYS = ("config", "configs", "index", "target", "meta", "base", "stop", "seed", "options")
const VISUALIZATION_KEYS = ("config", "base", "stop", "snap")

"""
    simulationkwargs(S, request; config=(), options=(), paths=nothing, keys=SIMULATION_KEYS)

Translate a JSON request into keyword arguments for `simulate` and friends.
`config` and `options` are server-side bases merged under the request values.
Variable names in `index`, `target`, `base`, `meta`, `stop` and `snap` are
validated against `paths` when given.
"""
simulationkwargs(S::Type{<:System}, r::APIDict; config=(), options=(), paths=nothing, keys=SIMULATION_KEYS) = begin
    kw = Dict{Symbol,Any}()
    base = configure(config, decodeconfig(get(r, "config", nothing)))
    if haskey(r, "configs") && "configs" in keys
        r["configs"] isa AbstractVector || apierror("`configs` must be an array of configurations")
        kw[:configs] = [configure(base, decodeconfig(c)) for c in r["configs"]]
    elseif !isempty(base)
        kw[:config] = base
    end
    for k in ("index", "target", "meta", "base")
        k in keys && haskey(r, k) || continue
        v = decodenames(r[k], paths)
        isnothing(v) || (kw[Symbol(k)] = v)
    end
    for k in ("stop", "snap")
        k in keys && haskey(r, k) || continue
        v = decode(r[k])
        isnothing(v) || (kw[Symbol(k)] = v isa AbstractString ? checkpath(v, paths) : v)
    end
    "seed" in keys && haskey(r, "seed") && !isnothing(r["seed"]) && (kw[:seed] = decodetyped(r["seed"], Int))
    for k in ("nounit", "long")
        k in keys && haskey(r, k) && !isnothing(r[k]) && (kw[Symbol(k)] = parsebool(r[k]))
    end
    if "options" in keys
        o = merge(decodeoptions(options), decodeoptions(get(r, "options", nothing)))
        isempty(o) || (kw[:options] = o)
    end
    kw
end

decodenames(::Nothing, paths) = nothing
decodenames(v::AbstractString, paths) = checkpath(v, paths)
decodenames(v::AbstractVector, paths) = Any[decodenames(x, paths) for x in v]
decodenames(v::AbstractDict, paths) = [Symbol(k) => checkpath(String(x), paths) for (k, x) in stringkeys(v)]
decodenames(v, paths) = v

checkpath(v::AbstractString, ::Nothing) = v
checkpath(v::AbstractString, paths) = (v == "*" || v in paths || startswith(v, "context.")) ? v : apierror("Unknown variable path `$v`")

decodeobserved(r::APIDict) = begin
    obs = get(r, "observed", get(r, "obs", nothing))
    isnothing(obs) && apierror("evaluate/calibrate requires `observed`")
    df = decode(obs)
    df isa DataFrame || apierror("`observed` must be a CSV or DataFrame table payload")
    df
end

"""`xstep` for `visualize`: `{"path": "S.a", "start": 1, "stop": 5, "step": 1, "unit": "m"}` or `{"path": ..., "values": [...]}`."""
decodestep(::Nothing) = nothing
decodestep(x::AbstractDict) = begin
    d = stringkeys(x)
    path = haskey(d, "path") ? String(d["path"]) : haskey(d, "system") && haskey(d, "name") ? "$(d["system"]).$(d["name"])" :
        apierror("`xstep` requires `path` or `system` and `name`")
    parts = split(path, ".")
    length(parts) == 2 || apierror("`xstep` path must be `System.parameter`")
    values = if haskey(d, "values")
        decode(d["values"])
    else
        start = decode(get(d, "start", get(d, "min", nothing)))
        stop = decode(get(d, "stop", get(d, "max", nothing)))
        step = decode(get(d, "step", nothing))
        any(isnothing, (start, stop, step)) && apierror("`xstep` requires `start`, `stop` and `step` (or `values`)")
        u = parseunit(get(d, "unit", nothing))
        if !isnothing(u)
            start, stop = unitfy(start, u), unitfy(stop, u)
            step = unitfy(step, Unitful.absoluteunit(u))
        end
        start:step:stop
    end
    Symbol(parts[1]) => Symbol(parts[2]) => values
end
decodestep(x) = apierror("`xstep` must be an object")

const PLOT_OPTIONS = ("kind", "title", "xlab", "ylab", "legend", "legendpos", "names", "colors", "xlim", "ylim", "xunit", "yunit", "aspect", "linestyle", "linestyles")

decodeplot(x) = begin
    d = stringkeys(x)
    kw = Dict{Symbol,Any}()
    for (k, v) in d
        k in PLOT_OPTIONS || apierror("Unsupported plot option `$k`")
        key = k == "linestyles" ? :linestyle : Symbol(k)
        kw[key] = if key in (:kind, :legendpos)
            v isa AbstractString ? Symbol(v) : v
        elseif key == :linestyle
            v isa AbstractVector ? Symbol.(v) : Symbol(v)
        elseif key in (:xlim, :ylim)
            v isa AbstractVector && length(v) == 2 || apierror("`$k` must be a two-element array")
            (v[1], v[2])
        elseif key in (:xunit, :yunit)
            parseunit(v)
        else
            v
        end
    end
    kw
end

# --- operations ---------------------------------------------------------------

operationpayload(S, operation; kw...) = APIDict(
    "status" => "ok",
    "contract_version" => API_CONTRACT_VERSION,
    "model" => string(nameof(S)),
    "operation" => operation,
    (string(k) => v for (k, v) in kw)...,
)

"""
    simulate_payload(S, request; config=(), options=(), paths=nothing)

Run `simulate(S; ...)` from a JSON request and return a table payload.
"""
simulate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), paths=nothing) = begin
    r = stringkeys(request)
    kw = simulationkwargs(S, r; config, options, paths)
    verbose = parsebool(get(stringkeys(get(r, "api_options", nothing)), "verbose", false))
    elapsed = @elapsed df = simulate(S; kw..., verbose)
    tablepayload(df; model=string(nameof(S)), elapsed)
end

"""
    evaluate_payload(S, request; config=(), options=(), paths=nothing)

Run `evaluate(S, observed; ...)` from a JSON request. `observed` is a table
payload; `target` is required and `metric` names the metric function.
"""
evaluate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), paths=nothing) = begin
    r = stringkeys(request)
    obs = decodeobserved(r)
    kw = simulationkwargs(S, r; config, options, paths, keys=EVALUATION_KEYS)
    haskey(kw, :target) || apierror("evaluate requires `target`")
    haskey(r, "metric") && !isnothing(r["metric"]) && (kw[:metric] = Symbol(r["metric"]))
    elapsed = @elapsed value = evaluate(S, obs; kw...)
    values = value isa Union{Tuple,AbstractVector} ? collect(value) : [value]
    all(v -> (x = deunitfy(v); x isa Number && isfinite(x)), values) ||
        apierror("Metric is not finite; check that observations match the simulation index and targets")
    operationpayload(S, "evaluate";
        metric = string(get(kw, :metric, :rmse)),
        target = encode(kw[:target]),
        value = value isa Union{Tuple,AbstractVector} ? [encodevalue(v) for v in values] : encodevalue(value),
        summary = APIDict("nobs" => nrow(obs), "elapsed_ms" => round(Int, elapsed * 1000)),
    )
end

"""
    calibrate_payload(S, request; config=(), options=(), paths=nothing)

Run `calibrate(S, observed; ...)` from a JSON request. `parameters` maps
configuration paths to `[lower, upper]` bounds (or `{lower, upper, unit}`
objects) in the same nested or flat shape as `config`.
"""
calibrate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), paths=nothing) = begin
    r = stringkeys(request)
    obs = decodeobserved(r)
    kw = simulationkwargs(S, r; config, options, paths, keys=EVALUATION_KEYS)
    haskey(kw, :target) || apierror("calibrate requires `target`")
    haskey(r, "parameters") || apierror("calibrate requires `parameters`")
    kw[:parameters] = decodeconfig(r["parameters"]; value=decodebounds)
    haskey(r, "metric") && !isnothing(r["metric"]) && (kw[:metric] = Symbol(r["metric"]))
    haskey(r, "weight") && !isnothing(r["weight"]) && (kw[:weight] = Float64.(decode(r["weight"])))
    haskey(r, "pareto") && !isnothing(r["pareto"]) && (kw[:pareto] = parsebool(r["pareto"]))
    optim = decodeoptions(get(r, "optim", nothing))
    isempty(optim) || (kw[:optim] = optim)
    elapsed = @elapsed result = calibrate(S, obs; kw...)
    operationpayload(S, "calibrate";
        metric = string(get(kw, :metric, :rmse)),
        target = encode(kw[:target]),
        config = encode(result),
        summary = APIDict(
            "nobs" => nrow(obs),
            "nparameters" => length(parameterkeys(kw[:parameters])),
            "elapsed_ms" => round(Int, elapsed * 1000),
        ),
    )
end

"""
    visualize_payload(S, request; config=(), options=(), paths=nothing)

Render an SVG with `visualize`. A request either simulates `S` (`config`,
`stop`, `snap`, `base`, `xstep`) or plots a table given as `data`. Plot options
go under `plot` (`kind`, `title`, `xlab`, `ylab`, `legend`, `xlim`, `ylim`, ...).
"""
visualize_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), paths=nothing) = begin
    r = stringkeys(request)
    y = get(r, "y", get(r, "target", nothing))
    isnothing(y) && apierror("visualize requires `y` or `target`")
    x = decodenames(get(r, "x", "time"), paths)
    y = decodenames(y, paths)
    backend = get(r, "backend", "Makie")
    backend == "Makie" || apierror("Unsupported backend `$backend`; only Makie renders SVG")
    plot = decodeplot(get(r, "plot", APIDict()))
    haskey(r, "kind") && !isnothing(r["kind"]) && (plot[:kind] = Symbol(r["kind"]))
    elapsed = @elapsed p = if haskey(r, "data")
        df = decode(r["data"])
        df isa DataFrame || apierror("`data` must be a CSV or DataFrame table payload")
        visualize(df, x, y; plot..., backend=:Makie)
    else
        kw = simulationkwargs(S, r; config, options, paths, keys=VISUALIZATION_KEYS)
        xstep = decodestep(get(r, "xstep", nothing))
        isnothing(xstep) || (kw[:xstep] = xstep)
        visualize(S, x, y; kw..., plot..., backend=:Makie)
    end
    operationpayload(S, "visualize";
        format = "svg",
        content_type = "image/svg+xml",
        body = sprint(show, MIME("image/svg+xml"), p),
        summary = APIDict("elapsed_ms" => round(Int, elapsed * 1000)),
    )
end

# --- dashboard metadata -------------------------------------------------------

"""
    widgetpayload(S; config=(), ui=(), description=describe(S; config))

Dashboard metadata derived from [`describe`](@ref): editable `controls` (one per
parameter and table input, plus the runtime `Clock.step`), selectable `outputs`,
plot `panels` and the `simulation` defaults. `ui` may override `title`,
`outputs`, `panels`, `sweeps`, `table_inputs`, `stop` and `snap`.
"""
widgetpayload(S::Type{<:System}; config=(), ui=APIDict(), description=describe(S; config)) = begin
    d = description
    u = stringkeys(ui)
    outputs = filter(v -> v["role"] == "output", d["variables"])
    i = findfirst(v -> v["target"] == "time", outputs)
    time = isnothing(i) ? timeoutput(S) : popat!(outputs, i)
    requested = get(u, "outputs", nothing)
    if !isnothing(requested)
        matches = Dict{String,Any}()
        for v in outputs, key in (v["name"], v["target"], v["alias"])
            isnothing(key) || (matches[key] = v)
        end
        outputs = unique([matches[string(name)] for name in requested if haskey(matches, string(name))])
    end
    outputs = vcat([time], outputs)
    targets = Dict{String,String}()
    for v in outputs, key in (v["name"], v["target"], v["alias"])
        isnothing(key) || (targets[key] = v["target"])
    end
    controls = [control(p) for p in d["parameters"]]
    known = Set(c["path"] for c in controls)
    for t in d["tables"]
        t["path"] in known && continue
        push!(known, t["path"])
        push!(controls, control(t))
    end
    for c in controls
        c["role"] == "table" || continue
        t = findfirst(t -> t["path"] == c["path"], d["tables"])
        isnothing(t) || (c["columns"] = d["tables"][t]["columns"])
    end
    for spec in get(u, "table_inputs", [])
        s = stringkeys(spec)
        path = get(s, "path", nothing)
        isnothing(path) && apierror("table input specification requires `path`")
        i = findfirst(c -> c["role"] == "table" && path in (c["path"], c["declared"]), controls)
        isnothing(i) && apierror("table input specification does not match a provided table: $path")
        for key in ("label", "description", "accept", "columns", "default_filename")
            haskey(s, key) && (controls[i][key] = s[key])
        end
    end
    filter!(c -> c["path"] != "Clock.step", controls)
    push!(controls, clockcontrol(S, config))
    options = [v["target"] for v in outputs]
    x = "time"
    ys = filter(!=(x), options)
    panels = [normalizepanel(p, targets) for p in get(u, "panels", [APIDict("title" => "Panel 1", "x" => x, "y" => isempty(ys) ? [] : [first(ys)], "kind" => "line")])]
    payload = APIDict(
        "title" => get(u, "title", "$(d["model"]["name"]) Dashboard"),
        "contract" => d["contract"],
        "model" => d["model"],
        "systems" => d["systems"],
        "controls" => controls,
        "outputs" => outputs,
        "tables" => d["tables"],
        "simulation" => APIDict("stop" => get(u, "stop", APIDict("value" => 5, "unit" => "hr")), "snap" => get(u, "snap", nothing)),
        "visualize" => APIDict(
            "x" => APIDict("options" => options, "default" => x),
            "y" => APIDict("options" => options, "default" => isempty(ys) ? [] : [first(ys)]),
            "kind" => APIDict("options" => ["line", "scatter", "scatterline", "step"], "default" => "line"),
            "backend" => APIDict("options" => ["Makie"], "default" => "Makie"),
        ),
        "panels" => panels,
    )
    haskey(u, "sweeps") && (payload["sweeps"] = u["sweeps"])
    payload
end

"Editable control for a parameter or table entry of a description."
control(p::APIDict) = begin
    table = p["role"] == "table"
    default = get(p, "default", nothing)
    type = table ? "TableInput" : something(p["type"], default isa AbstractDict ? default["type"] : nothing, "")
    kind = table ? "file" : type == "Bool" ? "checkbox" : occursin(r"^(Int|UInt|Float)", type) || !isnothing(p["unit"]) ? "number" : "text"
    default = default isa AbstractDict ? default["value"] : nothing
    APIDict(
        "kind" => kind,
        "role" => table ? "table" : "parameter",
        "system" => p["system"],
        "name" => p["name"],
        "path" => p["path"],
        "declared" => p["declared"],
        "alias" => p["alias"],
        "label" => String(last(split(p["declared"], '.'))),
        "description" => p["description"],
        "unit" => p["unit"],
        "default" => default,
        "value_type" => type,
        "state" => p["state"],
        "min" => get(p["tags"], "min", nothing),
        "max" => get(p["tags"], "max", nothing),
        "step" => occursin(r"^(Int|UInt)", type) ? 1 : kind == "number" ? 0.1 : nothing,
        "accept" => table ? ".csv,text/csv" : nothing,
        "columns" => [],
        "source" => "dsl",
    )
end

normalizepanel(panel, targets) = begin
    p = stringkeys(panel)
    for k in ("x", "y")
        haskey(p, k) || continue
        p[k] = p[k] isa AbstractVector ? [get(targets, v, v) for v in p[k]] : get(targets, p[k], p[k])
    end
    p
end

"Clock type driving `S` (`Clock` unless a custom context is used)."
clocktype(S::Type{<:System}) = begin
    for (T, _, _) in systemtree(S; exclude=())
        T <: Clock && return T
    end
    Clock
end

timeoutput(S::Type{<:System}) = begin
    C = clocktype(S)
    v = only(filter(v -> v.name == :time, geninfos(C)))
    APIDict(
        "system" => string(namefor(C)), "name" => "time", "alias" => nothing,
        "path" => "$(namefor(C)).time", "declared" => "$(namefor(C)).time", "target" => "time",
        "description" => "Simulation time generated by the model clock.",
        "state" => "advance", "type" => typelabel(gettag(v, :_type, nothing)), "unit" => unitlabel(timeunit(C)),
        "role" => "output", "tags" => APIDict(), "dependencies" => String[], "source" => "runtime",
    )
end

clockcontrol(S::Type{<:System}, config) = begin
    C = clocktype(S)
    configured = configure(parameters(S; recursive=true, exclude=()), config)
    fields = get(configured, namefor(C), nothing)
    step = isnothing(fields) ? unitfy(1, timeunit(C)) : get(fields, :step, unitfy(1, timeunit(C)))
    v = encodevalue(step)
    APIDict(
        "kind" => "number", "role" => "parameter", "system" => string(namefor(C)), "name" => "step",
        "path" => "Clock.step", "declared" => "Clock.step", "alias" => nothing, "label" => "step",
        "description" => "Simulation time step exposed as a runtime configuration control.",
        "unit" => v["unit"], "default" => v["value"], "value_type" => v["type"], "state" => "preserve",
        "min" => nothing, "max" => nothing, "step" => 1, "accept" => nothing, "columns" => [], "source" => "runtime",
    )
end

# --- schema -------------------------------------------------------------------

"Request/response schema fragments: the components of the static OpenAPI document plus the route table."
apischema() = begin
    doc = JSON.parse(asset("openapi.json"))
    APIDict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "title" => "Cropbox Web API",
        "contract_version" => API_CONTRACT_VERSION,
        "routes" => [APIDict("method" => r.method, "path" => r.path, "operation" => string(r.op)) for r in API_ROUTES],
        "definitions" => get(get(doc, "components", APIDict()), "schemas", APIDict()),
    )
end

# --- entry points -------------------------------------------------------------

"""
    serve(S::Type{<:System}; host="127.0.0.1", port=8000, config=(), options=(), request_defaults=(), ui=(), dashboard=:static, async=false)

Expose a system through HTTP routes. Metadata routes publish the model
description from [`describe`](@ref) and the API schema; operation routes parse
JSON payloads and dispatch them to `simulate`, `visualize`, `evaluate` and
`calibrate`.

`config` and `options` are server-side bases for every request.
`request_defaults` holds trusted default request fields (for example a Julia
`snap` function) merged under each client request; its `config` is merged per
parameter path so a client value replaces the corresponding default.

Routes:
- `GET /api/model`, `GET /api/dashboard`, `GET /api/schema`, `GET /api/openapi`, `GET /api/docs`
- `POST /api/simulate`, `POST /api/visualize`, `POST /api/evaluate`, `POST /api/calibrate`
- `GET /` and `GET /dashboard` (bundled browser dashboard; `dashboard=:none` disables)

The call blocks while serving unless `async=true`, which returns the server
object. The service has no authentication or transport encryption; bind it to
loopback unless it is placed behind an appropriate gateway.
"""
serve(S::Type{<:System}; host="127.0.0.1", port=8000, config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static, async=false) = begin
    service = Service(S; config, options, request_defaults, ui, dashboard)
    handler = request -> begin
        status, type, body = respond(service, String(request.method), String(request.target), String(request.body))
        HTTP.Response(status, ["Content-Type" => type], body)
    end
    server = HTTP.serve!(handler, host, port)
    @info "Cropbox API server listening" host port=HTTP.port(server) model=string(nameof(S))
    async && return server
    try
        wait(server)
    finally
        close(server)
    end
    server
end

"""
    dashboard(S::Type{<:System}; frontend=:static, kwargs...)

Start the same service as [`serve`](@ref) with the browser frontend selected by
`frontend` (`:static` for the bundled client, `:none` for the API only, or a
custom `DashboardFrontend`).
"""
dashboard(S::Type{<:System}; frontend=:static, kwargs...) = serve(S; dashboard=frontend, kwargs...)

export describe, serve, dashboard
