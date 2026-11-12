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

const RUN_KEYS = ("config", "configs", "index", "target", "meta", "base", "stop", "seed")

"Request fields each operation accepts. Any other field is rejected, so that a misspelled one is not silently ignored."
const REQUEST_KEYS = (;
    simulate = (RUN_KEYS..., "snap", "nounit", "long"),
    evaluate = (RUN_KEYS..., "observed", "metric"),
    calibrate = (RUN_KEYS..., "observed", "metric", "parameters", "weight", "pareto", "optim"),
    visualize = ("config", "base", "stop", "snap", "x", "y", "kind", "plot", "xstep", "data"),
)

const JSON_TYPE = "application/json; charset=utf-8"
const HTML_TYPE = "text/html; charset=utf-8"

asset(name) = read(joinpath(@__DIR__, name), String)

"Paths that serve the bundled dashboard page: `/` and `/dashboard` for `:static`, a path of its own, or none for `:none` and `false`."
dashboardpaths(d::Symbol) = d == :static ? ["/", "/dashboard"] : d == :none ? String[] : error("unsupported dashboard: $d. Use :static, :none, false or a path.")
dashboardpaths(d::Bool) = d ? dashboardpaths(:static) : String[]
dashboardpaths(::Nothing) = String[]
dashboardpaths(path::AbstractString) = startswith(path, "/") ? [String(path)] : error("a dashboard path must start with /")

# --- service ------------------------------------------------------------------

"""
    Service(S; config=(), options=(), request_defaults=(), ui=(), dashboard=:static)

A configured web service for system `S`: the base configuration (with the
default one merged over it), the constructor options, the default request
fields, the index used to validate requests and the precomputed `GET`
responses. Use `respond` to handle a request without an HTTP server.
"""
struct Service
    system::Type
    config::Config
    options::NamedTuple
    defaults::APIDict
    index::ModelIndex
    cache::Dict{String,Tuple{Int,String,String}}
end

Service(S::Type{<:System}; config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static) = begin
    tree = systemtree(S)
    V = variables(tree)
    index = ModelIndex(tree, V)
    defaults = asobject(request_defaults)
    # A default configuration is decoded once and becomes part of the base configuration. Each is made
    # canonical first, so that a default replaces a base value whichever of the parameter's names either used.
    default = checkconfig(decodeconfig(pop!(defaults, "config", nothing)), index)
    c = configure(canonical(configure(config), index), canonical(default, index))
    checkkeys(defaults, unique(Iterators.flatten(REQUEST_KEYS)), "`request_defaults`")
    options = decodeoptions(options)
    d = description(S, tree, V; config=c)
    json(x) = (200, JSON_TYPE, JSON.json(x))
    cache = Dict{String,Tuple{Int,String,String}}(
        "/api/model" => json(d),
        "/api/dashboard" => json(widgetpayload(S; config=c, ui, defaults, description=d)),
        "/api/schema" => json(apischema()),
        "/api/openapi" => (200, JSON_TYPE, asset("openapi.json")),
        "/api/docs" => (200, HTML_TYPE, asset("swagger.html")),
        "/docs" => (200, HTML_TYPE, asset("swagger.html")),
    )
    for p in dashboardpaths(dashboard)
        cache[p] = (200, HTML_TYPE, asset("dashboard.html"))
    end
    Service(S, c, options, defaults, index, cache)
end

"""
    respond(service, method, target, body="") -> (status, content_type, body)

Handle one HTTP request against a `Service`. `GET` routes come from the
precomputed cache; `POST` routes parse the JSON body, fill in the fields it
leaves out from `request_defaults` and run the operation. Errors are reported
as JSON with HTTP status 400 (malformed JSON), 404/405 (routing), 422 (a
request the model or its data cannot take) or 500 (a failure while the model
runs).
"""
respond(s::Service, method::AbstractString, target::AbstractString, body::AbstractString="") = begin
    path = try
        HTTP.URI(target).path
    catch
        target
    end
    try
        if haskey(s.cache, path)
            method == "GET" || apierror("Method $method is not allowed for $path", "method")
            return s.cache[path]
        end
        route = findfirst(r -> r.path == path, API_ROUTES)
        isnothing(route) && apierror("No route for $path", "routing")
        method == "POST" || apierror("Method $method is not allowed for $path", "method")
        op = API_ROUTES[route].op
        payload = OPERATIONS[op](s.system, applydefaults(s, parserequest(body), op); config=s.config, options=s.options, index=s.index)
        return (200, JSON_TYPE, JSON.json(payload))
    catch e
        return errorresponse(rootcause(e); path)
    end
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
A client request with the fields it leaves out filled in from the trusted
`request_defaults` of the service, as far as the operation has them: what the
client sends wins. (A default `config` is not among them. It is part of the
service configuration, over which a client's is merged parameter by parameter.)
"""
applydefaults(s::Service, request::APIDict, op::Symbol) = merge(filter(p -> p.first in REQUEST_KEYS[op], s.defaults), request)

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

# What went wrong in a threaded run, without the stack traces its task wrappers print.
rootcause(e::TaskFailedException) = rootcause(e.task.result)
rootcause(e::CompositeException) = isempty(e.exceptions) ? e : rootcause(first(e.exceptions))
rootcause(e) = e

# --- requests -----------------------------------------------------------------

"A request as an object with string keys, holding only the fields its operation accepts."
requestobject(request::AbstractDict, op::Symbol) = checkkeys(stringkeys(request), REQUEST_KEYS[op], "the $op request")

"""
Run `f` on what the client sent: an error of type `E` there is the request's
(422 `validation`), not an execution failure. That is any error while a request
is decoded, and the `ArgumentError` with which Cropbox rejects data it cannot
use (observations that match no output, one label for two series). What a
model raises while it runs, of whatever type, arrives wrapped by the task that
ran it and stays an execution failure.
"""
validating(f, E=Exception) = try
    f()
catch e
    e isa E && !(e isa Union{APIRequestError,InterruptException}) || rethrow()
    apierror(first(split(sprint(showerror, e), '\n')))
end

"""
    simulationkwargs(request; config=(), options=(), index=nothing, fields=REQUEST_KEYS.simulate)

Translate the `fields` of a JSON request into keyword arguments for `simulate`
and friends. `config` is the server-side base that request configurations are
merged over, one for each of `configs` or each value of `xstep`; `options`,
the constructor options, are the service's alone. With a `ModelIndex`,
configurations, the variable names in `index`, `target`, `base`, `stop` and
`snap`, and the unit of a `stop` or `snap` duration are checked against the
model.
"""
simulationkwargs(r::APIDict; config=(), options=(), index=nothing, fields=REQUEST_KEYS.simulate) = begin
    kw = Dict{Symbol,Any}()
    field(k) = k in fields ? get(r, k, nothing) : nothing
    client(x) = canonical(checkconfig(decodeconfig(x), index), index)
    base = configure(config, client(field("config")))
    C = field("configs")
    C isa Union{Nothing,AbstractVector} || apierror("`configs` must be an array of configurations")
    steps = decodestep(field("xstep"), index)
    if !isnothing(steps)
        configs = kw[:configs] = [configure(base, c) for c in steps]
    elseif isnothing(C) || isempty(C)
        # without configurations of its own, `configs` runs the single one
        configs = [base]
        isempty(base) || (kw[:config] = base)
    else
        configs = kw[:configs] = [configure(base, client(c)) for c in C]
    end
    root = field("base")
    isnothing(root) || (kw[:base] = checkbase(root, index))
    for k in ("index", "target")
        v = decodenames(field(k), index; base=root)
        isnothing(v) || (kw[Symbol(k)] = v)
    end
    haskey(kw, :index) && (kw[:index] = clockindex(kw[:index], index; base=root))
    isnothing(field("meta")) || (kw[:meta] = decodemeta(field("meta"), configs))
    for k in ("stop", "snap")
        v = decode(field(k))
        isnothing(v) && continue
        if k == "snap" && v isa Real && !(v isa Bool)
            apierror("`snap` must be an interval such as `{\"value\": 1, \"unit\": \"d\"}`, a boolean or a variable path")
        elseif !(v isa Union{Number,AbstractString,Symbol,Function})
            apierror("`$k` must be a number, a quantity or a variable path")
        elseif v isa Quantity && !isnothing(index) && Unitful.dimension(v) != Unitful.dimension(index.time)
            apierror("`$k` takes a duration such as `{\"value\": 1, \"unit\": \"$(unitlabel(index.time))\"}`, not `$v`")
        end
        kw[Symbol(k)] = v isa AbstractString ? checkpath(v, index) : v
    end
    isnothing(field("seed")) || (kw[:seed] = decodetyped(field("seed"), Int))
    for k in ("nounit", "long")
        isnothing(field(k)) || (kw[Symbol(k)] = parsebool(field(k)))
    end
    isempty(options) || (kw[:options] = decodeoptions(options))
    kw
end

"""
    checkconfig(config, index)

Check a client configuration against the model. Every entry has to set a
parameter of the model, by any name Cropbox reads it from. A table input takes
a table payload and nothing else does; the other values are read as
`parametervalue` reads them.
"""
checkconfig(c::Config, ::Nothing) = c
checkconfig(c::Config, index::ModelIndex) = begin
    P = Pair[]
    for (system, F) in c, (name, value) in F
        path = "$(system).$(name)"
        K = get(index.parameters, path, nothing)
        isnothing(K) && apierror("Unknown parameter `$path`")
        table = any(v -> v.role == "table", K)
        table == (value isa DataFrame) || apierror(table ? "Table parameter `$path` requires a CSV or DataFrame payload" : "Parameter `$path` does not take a table")
        push!(P, system => name => parametervalue(value, first(K), path))
    end
    isempty(P) ? c : configure(P...)
end

"""
A value as the parameter `v` takes it: a string is read as the declared type,
nested arrays as the matrix a `tabulate` or `interpolate` parameter takes, and
a float as the exact value of a rational parameter (the clock step). A
parameter of a scalar type takes no array, and a quantity for it is converted
to the declared unit here, so that one it cannot be converted from is the
request's error rather than a failure to construct the model.
"""
parametervalue(value, v, path) = begin
    matrix = v.state in (:Tabulate, :Interpolate)
    scalar = !matrix && (v.type in keys(API_TYPES) || v.type == "Rational{Int64}")
    scalar && value isa AbstractVector && apierror("Parameter `$path` takes one value, not an array")
    if value isa AbstractString && !(v.type in (nothing, "String"))
        value = decodetyped(value, v.type)
    elseif matrix && value isa AbstractVector && !isempty(value) && all(x -> x isa AbstractVector, value)
        value = asmatrix(value)
    elseif v.type == "Rational{Int64}"
        value = exactify(Rational{Int}, value; warn=false)
    end
    scalar && value isa Quantity || return value
    try
        unitfy(value, v.unit)
    catch
        apierror("Parameter `$path` takes $(something(unitlabel(v.unit), "no unit")), not `$value`")
    end
end

"""
The parameters a configuration path sets, as ones to vary (`xstep`,
calibration): the path has to be known and no table. They are varied through
their own configuration paths (`config` of each), which Cropbox reads before
any other spelling.
"""
variedparameters(path::AbstractString, index::ModelIndex) = begin
    K = get(index.parameters, path, nothing)
    isnothing(K) && apierror("Unknown parameter `$path`")
    any(v -> v.role == "table", K) && apierror("Table parameter `$path` cannot be varied")
    K
end

# Paths indexing into produced or bundled systems (`leaves[1].area`, `leaves/*`) only resolve at run time.
const DYNAMIC_PATH = r"[\[\]/]"

"""
Check a variable path against the model. With `base`, the path is relative to
that system. Every part of it may be an alias; indexed paths are left for
Cropbox to resolve.
"""
checkpath(v::AbstractString, ::Nothing; base=nothing) = v
checkpath(v::AbstractString, index::ModelIndex; base=nothing) = begin
    p = isnothing(base) ? v : "$base.$v"
    occursin(DYNAMIC_PATH, p) || byname(p, index) in index.paths || apierror("Unknown variable path `$p`")
    v
end

# an access path with every alias replaced by the name it stands for
byname(p::AbstractString, index::ModelIndex) = foldl(split(p, "."); init="") do path, part
    k = isempty(path) ? String(part) : "$path.$part"
    get(index.aliases, k, k)
end

checkbase(b::AbstractString, ::Nothing) = b
checkbase(b::AbstractString, index::ModelIndex) =
    occursin(DYNAMIC_PATH, b) || "$(byname(b, index)).*" in index.paths ? b : apierror("Unknown system path `$b`")
checkbase(b, index) = apierror("`base` must be a system path")

"Variable names: a path, an array of paths, or an object mapping output column names to paths. `time` is the clock time."
decodenames(::Nothing, index; base=nothing) = nothing
decodenames(v::AbstractString, index; base=nothing) = v == "time" ? v : checkpath(v, index; base)
decodenames(v::AbstractVector, index; base=nothing) = Any[decodenames(x, index; base) for x in v]
decodenames(v::AbstractDict, index; base=nothing) =
    [Symbol(k) => (x isa AbstractString ? decodenames(x, index; base) : apierror("Column `$k` must name a variable path")) for (k, x) in v]
decodenames(v::Number, index; base=nothing) = apierror("Variable names must be a path, an array of paths or an object mapping column names to paths")
decodenames(v, index; base=nothing) = v  # a Julia value from the trusted `request_defaults`

# As an index `time` is the clock time, the default index, unless the model has a variable of that name.
clockindex(v::AbstractString, index::ModelIndex; base=nothing) =
    v == "time" && !(byname(isnothing(base) ? v : "$base.$v", index) in index.paths) ? (:time => "context.clock.time") : v
clockindex(v::AbstractVector, index::ModelIndex; base=nothing) = Any[clockindex(x, index; base) for x in v]
clockindex(v, index; base=nothing) = v

"""
`meta` adds columns to the result: a system name contributes that system's
configured parameters (so every configuration must have some), and an object
contributes its entries as constant columns.
"""
decodemeta(v::AbstractString, configs) = begin
    s = Symbol(v)
    all(c -> haskey(c, s), configs) || apierror("`meta` system `$v` has no configured parameters")
    s
end
decodemeta(v::AbstractVector, configs) = Any[decodemeta(x, configs) for x in v]
decodemeta(v::AbstractDict, configs) = Pair{Symbol,Any}[Symbol(k) => decode(x) for (k, x) in v]
decodemeta(v::Number, configs) = apierror("`meta` must be a system name, an array of them or an object of constant columns")
decodemeta(v, configs) = v  # a Julia value from the trusted `request_defaults`

decodemetric(m) = begin
    metric = Symbol(m)
    try
        metricfunc(metric)
    catch
        apierror("Unsupported metric `$m`")
    end
    metric
end

"""
`xstep` for `visualize`, the parameter varied across simulations:
`{"path": "S.a", "start": 1, "stop": 5, "step": 1, "unit": "m"}` or
`{"path": ..., "values": [...], "unit": "m"}`. Returns one configuration per
value, each read as `parametervalue` reads it.
"""
decodestep(::Nothing, index=nothing) = nothing
decodestep(x::AbstractDict, index=nothing) = begin
    d = checkkeys(stringkeys(x), ("path", "values", "start", "stop", "step", "unit"), "`xstep`")
    path = get(d, "path", nothing)
    path isa AbstractString && count(==('.'), path) == 1 || apierror("`xstep` requires `path`, a `System.parameter` configuration path")
    values = if !isnothing(get(d, "values", nothing))
        d["values"] isa AbstractVector || apierror("`xstep` values must be an array")
        decode(d["values"])
    else
        start, stop, step = (decode(get(d, k, nothing)) for k in ("start", "stop", "step"))
        all(v -> v isa Number, (start, stop, step)) || apierror("`xstep` requires numeric `start`, `stop` and `step` (or `values`)")
        start:step:stop
    end
    isempty(values) && apierror("`xstep` has no values")
    u = parseunit(get(d, "unit", nothing))
    isnothing(u) || (values = unitfy(values, u))
    isnothing(index) && return [configure(path => x) for x in values]
    K = variedparameters(path, index)
    [configure((v.config => parametervalue(x, v, path) for v in K)...) for x in values]
end
decodestep(x, index=nothing) = apierror("`xstep` must be an object")

const PLOT_OPTIONS = ("title", "xlab", "ylab", "legend", "legendpos", "names", "colors", "xlim", "ylim", "xunit", "yunit", "aspect", "linestyle")
const PLOT_KINDS = ("line", "scatter", "scatterline", "step")
const LINE_STYLES = ("solid", "dash", "dot", "dashdot", "dashdotdot")

choice(v, options, what) = v in options ? Symbol(v) : apierror("Unsupported $what `$v`; use one of $(join(options, ", "))")

decodeplot(x) = begin
    kw = Dict{Symbol,Any}()
    for (k, v) in checkkeys(asobject(x), PLOT_OPTIONS, "`plot`")
        isnothing(v) && continue
        kw[Symbol(k)] = if k == "linestyle"
            v isa AbstractVector ? [choice(s, LINE_STYLES, "line style") for s in v] : choice(v, LINE_STYLES, "line style")
        elseif k == "legendpos"
            v isa AbstractString ? Symbol(v) : v
        elseif k in ("xlim", "ylim")
            v isa AbstractVector && length(v) == 2 || apierror("`$k` must be a two-element array")
            (v[1], v[2])
        elseif k in ("xunit", "yunit")
            parseunit(v)
        else
            v
        end
    end
    kw
end

"Column names of a `data` table used as `x` or `y`."
tablecolumns(v::AbstractString, names) = v in names ? v : apierror("`data` has no column `$v`")
tablecolumns(v::AbstractVector, names) = Any[tablecolumns(x, names) for x in v]
tablecolumns(v, names) = apierror("`x` and `y` must name columns of `data`")

# --- operations ---------------------------------------------------------------

operationpayload(S, operation; kw...) = APIDict(
    "status" => "ok",
    "contract_version" => API_CONTRACT_VERSION,
    "model" => string(nameof(S)),
    "operation" => operation,
    (string(k) => v for (k, v) in kw)...,
)

"""
    simulate_payload(S, request; config=(), options=(), index=nothing)

Run `simulate(S; ...)` from a JSON request and return a table payload.
"""
simulate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), index=nothing) = begin
    kw = validating(() -> simulationkwargs(requestobject(request, :simulate); config, options, index))
    elapsed = @elapsed df = simulate(S; kw..., verbose=false)
    tablepayload(df; model=string(nameof(S)), elapsed)
end

"Observations and keyword arguments shared by `evaluate` and `calibrate` requests."
observationkwargs(r::APIDict, operation; kwargs...) = begin
    obs = decode(get(r, "observed", nothing))
    obs isa DataFrame || apierror("$operation requires `observed`, a CSV or DataFrame table payload")
    kw = simulationkwargs(r; kwargs..., fields=REQUEST_KEYS.evaluate)
    haskey(kw, :target) || apierror("$operation requires `target`")
    isnothing(get(r, "metric", nothing)) || (kw[:metric] = decodemetric(r["metric"]))
    (obs, kw)
end

"""
    evaluate_payload(S, request; config=(), options=(), index=nothing)

Run `evaluate(S, observed; ...)` from a JSON request. `observed` is a table
payload; `target` is required and `metric` names the metric function.
"""
evaluate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), index=nothing) = begin
    obs, kw = validating(() -> observationkwargs(requestobject(request, :evaluate), "evaluate"; config, options, index))
    elapsed = @elapsed value = validating(() -> evaluate(S, obs; kw...), ArgumentError)
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

"Optimizer options that write files where the service runs, which a client may not set."
const SERVER_OPTIM_OPTIONS = ("SaveTrace", "SaveFitnessTraceToCsv", "SaveParameters")

"""
    calibrate_payload(S, request; config=(), options=(), index=nothing)

Run `calibrate(S, observed; ...)` from a JSON request. `parameters` maps
configuration paths to `[lower, upper]` bounds (or `{lower, upper, unit}`
objects) in the same nested or flat shape as `config`.
"""
calibrate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), index=nothing) = begin
    obs, kw = validating() do
        r = requestobject(request, :calibrate)
        o, k = observationkwargs(r, "calibrate"; config, options, index)
        P = decodeconfig(get(r, "parameters", nothing); value=decodebounds)
        isempty(P) && apierror("calibrate requires `parameters` with at least one range")
        k[:parameters] = configure((calibrationrange(p, index) for p in flatconfig(P))...)
        isnothing(get(r, "weight", nothing)) || (k[:weight] = Float64.(decode(r["weight"])))
        isnothing(get(r, "pareto", nothing)) || (k[:pareto] = parsebool(r["pareto"]))
        optim = asobject(get(r, "optim", nothing))
        any(in(keys(optim)), SERVER_OPTIM_OPTIONS) && apierror("`optim` options that write files on the server are not available: $(join(SERVER_OPTIM_OPTIONS, ", "))")
        isempty(optim) || (k[:optim] = decodeoptions(optim))
        (o, k)
    end
    elapsed = @elapsed result = validating(() -> calibrate(S, obs; kw...), ArgumentError)
    operationpayload(S, "calibrate";
        metric = string(get(kw, :metric, :rmse)),
        target = encode(kw[:target]),
        config = calibrated(result, index),
        summary = APIDict(
            "nobs" => nrow(obs),
            "nparameters" => length(parameterkeys(kw[:parameters])),
            "elapsed_ms" => round(Int, elapsed * 1000),
        ),
    )
end

# `calibrate` searches plain numbers and only knows the units of systems defined in `Main`:
# a range goes in under the parameter's own path, in its declared unit, and comes out in it.
calibrationrange(p::Pair, ::Nothing) = p
calibrationrange((path, bounds)::Pair, index::ModelIndex) = begin
    K = variedparameters(path, index)
    length(K) == 1 || apierror("`$path` sets parameters of several systems ($(join((v.config for v in K), ", "))); calibrate one of them")
    v = only(K)
    v.config => map(b -> deunitfy(unitfy(b, v.unit)), bounds)
end

calibrated(c::Config, index) = APIDict(string(s) => APIDict(string(k) => encodevalue(v, declaredunit("$s.$k", index)) for (k, v) in F) for (s, F) in c)
calibrated(pareto::AbstractDict, index) = APIDict(string(fitness) => calibrated(c, index) for (fitness, c) in pareto)
declaredunit(path, ::Nothing) = nothing
declaredunit(path, index::ModelIndex) = first(index.parameters[path]).unit

"""
    visualize_payload(S, request; config=(), options=(), index=nothing)

Render an SVG of `y` against `x`: the columns of a table given as `data`, or
variables of `S`, which is then simulated first (`config`, `stop`, `snap`,
`base`, and `xstep` for one run per value of a parameter). `kind` selects the
plot and options go under `plot` (`title`, `xlab`, `ylab`, `legend`, `xlim`,
`ylim`, ...). One table is drawn either way, a single `y` named on its axis
and several in a legend; the grouped, layered and observation forms of
`visualize` have no request.
"""
visualize_payload(S::Type{<:System}, request::AbstractDict; config=(), options=(), index=nothing) = begin
    source, x, y, plot = validating(() -> plotarguments(requestobject(request, :visualize); config, options, index))
    # one series is named on its axis rather than in a legend, as `visualize(S, x, y)` does
    y isa AbstractVector || (get!(plot, :ylab, y); get!(plot, :names, [""]))
    elapsed = @elapsed begin
        table = source isa DataFrame ? source : simulate(S; source..., target=vcat(x, y), verbose=false)
        # no model runs here: what fails on the table is the request's choice of columns, units or labels
        p = validating(() -> visualize(table, x, vcat(y); plot..., backend=:Makie), Union{ArgumentError,Unitful.DimensionError})
    end
    operationpayload(S, "visualize";
        format = "svg",
        content_type = "image/svg+xml",
        body = sprint(show, MIME("image/svg+xml"), p),
        summary = APIDict("elapsed_ms" => round(Int, elapsed * 1000)),
    )
end

"What a visualize request plots: the `data` table or the `simulate` arguments that give one, the names of `x` and `y` in it, and the plot options."
plotarguments(r::APIDict; config=(), options=(), index=nothing) = begin
    x, y = something(get(r, "x", nothing), "time"), get(r, "y", nothing)
    x isa AbstractString || apierror("`x` must name one variable")
    y isa AbstractString || y isa AbstractVector && !isempty(y) && all(v -> v isa AbstractString, y) ||
        apierror("visualize requires `y`, a variable or an array of them")
    plot = decodeplot(get(r, "plot", nothing))
    isnothing(get(r, "kind", nothing)) || (plot[:kind] = choice(r["kind"], PLOT_KINDS, "plot kind"))
    styles = get(plot, :linestyle, nothing)
    styles isa AbstractVector && length(styles) != length(vcat(y)) && apierror("`linestyle` needs one style for each of `y`")
    if !isnothing(get(r, "data", nothing))
        df = decode(r["data"])
        df isa DataFrame || apierror("`data` must be a CSV or DataFrame table payload")
        columns = DataFrames.names(df)
        (df, tablecolumns(x, columns), tablecolumns(y, columns), plot)
    else
        kw = simulationkwargs(r; config, options, index, fields=REQUEST_KEYS.visualize)
        base = get(kw, :base, nothing)
        (kw, decodenames(x, index; base), decodenames(y, index; base), plot)
    end
end

const OPERATIONS = (; simulate=simulate_payload, visualize=visualize_payload, evaluate=evaluate_payload, calibrate=calibrate_payload)

# --- dashboard metadata -------------------------------------------------------

"""
    widgetpayload(S; config=(), ui=(), defaults=(), description=describe(S; config))

Dashboard metadata derived from [`describe`](@ref): editable `controls` (one per
parameter and table input, plus the runtime `Clock.step`), selectable `outputs`,
plot `panels` and the `simulation` settings to start from, which are the `stop`
and `snap` among the request `defaults` of the service. `ui` may set `title`,
`outputs`, `panels`, `sweeps` and `table_inputs`. Outputs and panel variables
are named by target, name or alias and may be parameters; the variables of
every panel are among the outputs.
"""
widgetpayload(S::Type{<:System}; config=(), ui=APIDict(), defaults=APIDict(), description=describe(S; config)) = begin
    d = description
    u = checkkeys(asobject(ui), ("title", "outputs", "panels", "sweeps", "table_inputs"), "`ui`")
    defaults = asobject(defaults)
    outputs = filter(v -> v["role"] == "output", d["variables"])
    i = findfirst(v -> v["target"] == "time", outputs)
    time = isnothing(i) ? timeoutput(S) : popat!(outputs, i)
    # an output may also be a parameter, e.g. a threshold drawn as a reference line
    named = entriesbyname(vcat([time], outputs, filter(p -> p["role"] == "parameter" && !isnothing(p["target"]), d["parameters"])))
    pick(name) = haskey(named, string(name)) ? named[string(name)] : error("dashboard variable `$name` is not one of $(d["model"]["name"])")
    isnothing(get(u, "outputs", nothing)) || (outputs = Any[pick(name) for name in u["outputs"]])
    panels = if isnothing(get(u, "panels", nothing))
        y = [v["target"] for v in outputs if v !== time]
        [APIDict("title" => "Panel 1", "x" => "time", "y" => y[1:min(1, end)], "kind" => "line")]
    else
        [panel(p, pick) for p in u["panels"]]
    end
    outputs = unique(vcat([time], outputs, [pick(name) for p in panels for name in vcat(p["x"], p["y"])]))
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
    for spec in something(get(u, "table_inputs", nothing), [])
        s = asobject(spec)
        path = get(s, "path", nothing)
        isnothing(path) && error("table input specification requires `path`")
        i = findfirst(c -> c["role"] == "table" && path in (c["path"], c["declared"]), controls)
        isnothing(i) && error("table input specification does not match a provided table: $path")
        for key in ("label", "description", "accept", "columns", "default_filename")
            haskey(s, key) && (controls[i][key] = s[key])
        end
    end
    filter!(c -> c["path"] != "Clock.step", controls)
    push!(controls, clockcontrol(S, config))
    payload = APIDict(
        "title" => get(u, "title", "$(d["model"]["name"]) Dashboard"),
        "model" => d["model"],
        "controls" => controls,
        "outputs" => outputs,
        "tables" => d["tables"],
        "simulation" => APIDict(
            "stop" => something(shown(get(defaults, "stop", nothing)), APIDict("value" => 5, "unit" => unitlabel(timeunit(clocktype(S))))),
            "snap" => shown(get(defaults, "snap", nothing)),
        ),
        "panels" => panels,
    )
    haskey(u, "sweeps") && (payload["sweeps"] = u["sweeps"])
    payload
end

# A default `stop` or `snap` as a dashboard can show it; a Julia function is left to the service.
shown(v::Function) = nothing
shown(v::Quantity) = encodevalue(v)
shown(v::Symbol) = string(v)
shown(v) = v

"""
Look up description entries by `target`, `name` or `alias`. An exact target
wins over a name and a name over an alias; among equals the first entry (the
one closest to the root system) wins.
"""
entriesbyname(entries) = begin
    lookup = Dict{String,Any}()
    for key in ("target", "name", "alias"), v in entries
        k = v[key]
        isnothing(k) || haskey(lookup, k) || (lookup[k] = v)
    end
    lookup
end

"A plot panel of the dashboard with the targets of the variables it names."
panel(spec, pick) = begin
    p = asobject(spec)
    p["x"] = pick(get(p, "x", "time"))["target"]
    p["y"] = [pick(name)["target"] for name in vcat(get(p, "y", []))]
    p
end

"Editable control for a parameter or table entry of a description."
control(p::APIDict) = begin
    table = p["role"] == "table"
    default = something(get(p, "default", nothing), APIDict())
    type = table ? "TableInput" : something(p["type"], get(default, "type", nothing), "")
    kind = table ? "file" : type == "Bool" ? "checkbox" : occursin(r"^(Int|UInt|Float)", type) || !isnothing(p["unit"]) ? "number" : "text"
    # a bound given as an expression of other variables is not one a control can enforce
    bound(k) = (b = get(p["tags"], k, nothing); b isa Real ? b : nothing)
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
        "default" => get(default, "value", nothing),
        "value_type" => type,
        "timezone" => get(default, "timezone", nothing),
        "state" => p["state"],
        "min" => bound("min"),
        "max" => bound("max"),
        "step" => occursin(r"^(Int|UInt)", type) ? 1 : kind == "number" ? 0.1 : nothing,
        "accept" => table ? ".csv,text/csv" : nothing,
        "columns" => [],
        "source" => "dsl",
    )
end

timeoutput(S::Type{<:System}) = begin
    C = clocktype(S)
    v = only(filter(v -> v.name == :time, geninfos(C)))
    e = entry(; system=namefor(C), name=:time, description="Simulation time generated by the model clock.",
        state=v.state, type=typelabel(gettag(v, :_type, nothing)), unit=timeunit(C), role="output")
    e["source"] = "runtime"
    e
end

clockcontrol(S::Type{<:System}, config) = begin
    C = clocktype(S)
    # the configured step, looked up the way the clock itself does, or its default
    step = option(configure(config), systemkeys(C), :step)
    ismissing(step) && (step = parameters(C)[namefor(C)][:step])
    e = entry(; system=namefor(C), name=:step, path="Clock.step", description="Simulation time step exposed as a runtime configuration control.",
        state=:Preserve, unit=unitof(step), role="parameter")
    e["default"] = encodevalue(step)
    c = control(e)
    c["step"], c["source"] = 1, "runtime"
    c
end

# --- schema -------------------------------------------------------------------

"Request/response schema fragments: the schemas of the static OpenAPI document, referring to each other as `#/definitions/...`, plus the route table."
apischema() = begin
    doc = JSON.parse(replace(asset("openapi.json"), "#/components/schemas/" => "#/definitions/"))
    APIDict(
        "\$schema" => "https://json-schema.org/draft/2020-12/schema",
        "title" => "Cropbox Web API",
        "contract_version" => API_CONTRACT_VERSION,
        "routes" => [APIDict("method" => r.method, "path" => r.path, "operation" => string(r.op)) for r in API_ROUTES],
        "definitions" => doc["components"]["schemas"],
    )
end

# --- entry points -------------------------------------------------------------

"""
    serve(S::Type{<:System}; host="127.0.0.1", port=8000, config=(), options=(), request_defaults=(), ui=(), dashboard=:static, async=false)

Expose a system through HTTP routes. Metadata routes publish the model
description from [`describe`](@ref) and the API schema; operation routes parse
JSON payloads and dispatch them to `simulate`, `visualize`, `evaluate` and
`calibrate`.

Every request starts from what the service was given, and what a client sends
wins over it:

- `config` is the base configuration. The `config` of `request_defaults`, in
  the JSON shape of a request, is merged over it once when the service starts,
  and the `config` of a request over the result: a value replaces the one
  below it whichever of the parameter's names (alias, mixin) either used.
- The other `request_defaults` (`stop`, `snap`, `target`, ...) stand in for the
  fields a request leaves out, in the operations that have them. They are
  trusted and may hold Julia values such as a `snap` function. The bundled
  dashboard starts from their `stop` and `snap`.
- `options`, the constructor options of the system (the values of its `extern`
  variables), are the service's alone: a request has no such field.

`ui` arranges the bundled dashboard: its `title`, `outputs`, `panels`,
`sweeps` and `table_inputs`.

Routes:
- `GET /api/model`, `GET /api/dashboard`, `GET /api/schema`, `GET /api/openapi`, `GET /api/docs`
- `POST /api/simulate`, `POST /api/visualize`, `POST /api/evaluate`, `POST /api/calibrate`
- `GET /` and `GET /dashboard` (bundled browser dashboard; `dashboard="/path"` serves it there instead and `dashboard=:none` disables it)

The call blocks while serving unless `async=true`, which returns the server
object. The service has no authentication or transport encryption; bind it to
loopback unless it is placed behind an appropriate gateway. Clients can only
set parameters that the model declares, and a table only from the data they
send, but a model may itself declare a parameter that names a file to read
(the `filename` of the store systems).
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

Start the same service as [`serve`](@ref). `frontend` is passed on as its
`dashboard` option: `:static` for the bundled browser client at `/` and
`/dashboard`, a path to serve it at instead, or `:none` for the API only.
"""
dashboard(S::Type{<:System}; frontend=:static, kwargs...) = serve(S; dashboard=frontend, kwargs...)

export describe, serve, dashboard
