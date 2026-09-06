using CSV: CSV
using DataFrames: DataFrame, nrow, names, eachrow
using DataStructures: OrderedDict
using Dates: Date, DateTime
using HTTP: HTTP
using JSON3: JSON3
using Sockets: Sockets
using TimeZones: TimeZone, ZonedDateTime, astimezone
using Unitful: Unitful, Quantity
import DataAPI: describe

const APIDict = Dict{String,Any}
const API_CONTRACT_VERSION = "0.1.0"
const API_PUBLIC_VARIABLE_TAGS = Set((
    :by, :from, :lower, :max, :maxiter, :min, :optional, :pick,
    :round, :roundunit, :to, :tol, :upper, :when,
))

struct APIRequestError <: Exception
    category::String
    message::String
end

Base.showerror(io::IO, e::APIRequestError) = print(io, e.message)
api_validation_error(message) = throw(APIRequestError("validation", String(message)))

api_state_name(state) = isnothing(state) ? nothing : lowercase(string(state))

abstract type DashboardFrontend end

struct NoDashboard <: DashboardFrontend end

struct StaticDashboard <: DashboardFrontend
    paths::Vector{String}
end

StaticDashboard(; path=nothing, paths=nothing) = begin
    route_paths = if !isnothing(paths)
        [String(p) for p in paths]
    elseif isnothing(path)
        ["/", "/dashboard"]
    else
        [String(path)]
    end
    isempty(route_paths) && error("dashboard paths must not be empty")
    any(p -> !startswith(p, "/"), route_paths) && error("dashboard paths must start with /")
    StaticDashboard(unique(route_paths))
end

dashboard_frontend(dashboard::DashboardFrontend) = dashboard
dashboard_frontend(::Nothing) = NoDashboard()
dashboard_frontend(dashboard::Bool) = dashboard ? StaticDashboard() : NoDashboard()
dashboard_frontend(dashboard::Symbol) = begin
    dashboard == :static && return StaticDashboard()
    dashboard == :none && return NoDashboard()
    error("unsupported dashboard frontend: $(dashboard). Use :static, :none, false, or a DashboardFrontend object.")
end
dashboard_frontend(path::AbstractString) = StaticDashboard(; path)

dashboard_routes(::DashboardFrontend) = ["/dashboard"]
dashboard_routes(::NoDashboard) = String[]
dashboard_routes(frontend::StaticDashboard) = frontend.paths

dashboard_route_response(frontend::DashboardFrontend, ::Type{<:System}; config=(), options=(), ui=APIDict()) =
    error("dashboard frontend $(typeof(frontend)) must implement Cropbox.dashboard_route_response")
dashboard_route_response(::StaticDashboard, ::Type{<:System}; config=(), options=(), ui=APIDict()) =
    200, "text/html; charset=utf-8", dashboard_html()

api_contract_metadata() = APIDict(
    "version" => API_CONTRACT_VERSION,
    "execution_model" => "stateless-request",
    "state_scope" => "Each HTTP request parses its payload and calls the requested Cropbox operation without retaining model state between requests.",
    "compatibility" => "The contract is experimental; clients should read /api/schema or /api/openapi for every service version.",
)

"""
    describe(S::Type{<:System}; config=(), recursive=true, exclude=(Context,))

Return a JSON-compatible description of a Cropbox system. The description is
an independent model-introspection result containing systems, variables,
parameters, state roles, units, documentation, configuration paths, and table
bindings. It can be used directly by external tools and is also the metadata
source for services started by [`serve`](@ref).
"""
describe(S::Type{<:System}; config=(), recursive=true, exclude=(Context,)) = begin
    contexts = api_system_contexts(S; recursive, exclude)
    all_variables = APIDict[]
    for ctx in contexts
        append!(all_variables, api_variable_entries(ctx))
    end
    parameter_targets = APIDict()
    for variable in all_variables
        variable["role"] == "parameter" || continue
        for path in variable["accepted_config_paths"]
            parameter_targets[path] = variable["target_path"]
        end
    end

    defaults = configure(parameters(S; recursive, exclude), config)
    flat = parameterflatten(defaults)
    units = parameterunits(collect(keys(flat)))
    info = parameter_info_map(S; recursive, exclude)
    declared_units = api_parameter_unit_map(contexts)
    params = [
        let meta = get(info, (system, name), nothing),
            declared_unit = get(declared_units, (system, name), nothing),
            effective_unit = isnothing(declared_unit) ? unit : declared_unit,
            config_path = isnothing(meta) ? api_config_path_for(system, name) : api_config_path_for(system, meta, name),
            accepted_paths = isnothing(meta) ? [config_path] : api_accepted_config_paths(system, meta, name)
        APIDict(
            "system" => string(system),
            "name" => string(name),
            "config_path" => config_path,
            "declared_path" => isnothing(meta) ? api_config_path_for(system, name) : api_config_path_for(meta.system, meta, name),
            "accepted_config_paths" => accepted_paths,
            "target_path" => get(parameter_targets, config_path, string(name)),
            "alias" => isnothing(meta) || isnothing(meta.alias) ? nothing : string(meta.alias),
            "description" => isnothing(meta) ? "" : strip(meta.docstring),
            "default" => if !isnothing(meta) && meta.state == :Provide
                APIDict("value" => nothing, "type" => "TableInput", "unit" => nothing)
            else
                encode_api_value(value, effective_unit)
            end,
            "unit" => encode_api_unit(effective_unit),
            "state" => isnothing(meta) ? nothing : api_state_name(meta.state),
            "tags" => isnothing(meta) ? APIDict() : api_variable_tags(meta),
            "dependencies" => isnothing(meta) ? [] : api_variable_dependencies(meta),
            "role" => isnothing(meta) ? "parameter" : api_variable_role(meta),
        )
        end
        for (((system, name), value), unit) in zip(flat, units)
    ]
    variables = filter(v -> v["role"] != "parameter", all_variables)
    for variable in variables
        delete!(variable, "accepted_config_paths")
    end
    tables = APIDict[]
    for ctx in contexts
        append!(tables, api_table_entries(ctx))
    end
    table_paths = Set(t["config_path"] for t in tables)
    for ((system, name), _) in flat
        meta = get(info, (system, name), nothing)
        isnothing(meta) && continue
        meta.state == :Provide || continue
        config_path = api_config_path_for(system, meta, name)
        config_path in table_paths && continue
        push!(table_paths, config_path)
        push!(tables, APIDict(
            "system" => string(system),
            "name" => string(name),
            "config_path" => config_path,
            "declared_path" => api_config_path_for(meta.system, meta, name),
            "accepted_config_paths" => api_accepted_config_paths(system, meta, name),
            "target_path" => get(parameter_targets, config_path, string(name)),
            "description" => strip(meta.docstring),
            "state" => "provide",
            "index" => api_tag_encoded(gettag(meta, :index, QuoteNode(:index))),
            "tags" => api_variable_tags(meta),
            "consumers" => APIDict[],
            "role" => "table",
        ))
    end
    systems = [
        APIDict(
            "name" => string(namefor(ctx.type)),
            "module" => string(parentmodule(ctx.type)),
            "root" => ctx.root,
            "access_path" => ctx.access_path,
        )
        for ctx in contexts
    ]
    APIDict(
        "contract" => APIDict("version" => API_CONTRACT_VERSION),
        "model" => APIDict(
            "name" => string(nameof(S)),
            "module" => string(parentmodule(S)),
        ),
        "systems" => systems,
        "parameters" => params,
        "variables" => variables,
        "tables" => tables,
    )
end

api_system_contexts(S::Type{<:System}; recursive=true, exclude=(Context,)) = begin
    contexts = []
    seen = Set{Tuple{DataType,String}}()

    function visit!(T::Type{<:System}, access_path::AbstractString, root::Bool)
        api_system_excluded(T, exclude) && return
        key = (typefor(T), String(access_path))
        key in seen && return
        push!(seen, key)
        push!(contexts, (; type=T, access_path=String(access_path), root))
        recursive || return
        for field in subsystemsof(T)
            child = fieldtype(typefor(T), field)
            child <: System || continue
            child_path = isempty(access_path) ? string(field) : "$(access_path).$(field)"
            visit!(child, child_path, false)
        end
    end

    visit!(S, "", true)
    contexts
end

api_system_excluded(T, exclude) = any(E -> T <: E, exclude)

"""
    widget_payload(S::Type{<:System}; config=(), ui=APIDict())

Return a backend-agnostic widget schema generated from `describe(S)`. Browser
dashboards, Genie/Stipple apps, and notebooks can use this schema without
duplicating Cropbox model introspection.
"""
widget_payload(S::Type{<:System}; config=(), ui=APIDict(), description=nothing) = begin
    d = isnothing(description) ? describe(S; config) : description
    ui_ = stringkeydict(ui)
    requested_outputs = get(ui_, "outputs", nothing)
    model_outputs = filter(v -> v["role"] == "output" && get(v, "target_path", nothing) != "time", d["variables"])
    time_index = findfirst(v -> v["role"] == "output" && get(v, "target_path", nothing) == "time", d["variables"])
    time_output = isnothing(time_index) ? api_time_output(S, config) : d["variables"][time_index]
    available_outputs = vcat([time_output], model_outputs)
    outputs = if isnothing(requested_outputs)
        available_outputs
    else
        requested = collect(requested_outputs)
        matches = Dict{Any,Any}()
        for v in available_outputs
            matches[v["name"]] = v
            matches[get(v, "path", v["name"])] = v
            matches[get(v, "target_path", v["name"])] = v
            alias = get(v, "alias", nothing)
            isnothing(alias) || (matches[alias] = v)
        end
        selected = unique([matches[name] for name in requested if haskey(matches, name)])
        time = first(available_outputs)
        any(v -> get(v, "target_path", nothing) == "time", selected) ? selected : vcat([time], selected)
    end
    output_path(v) = get(v, "target_path", v["name"])
    output_matches = Dict{Any,Any}()
    for v in outputs
        path = output_path(v)
        output_matches[v["name"]] = path
        output_matches[get(v, "path", v["name"])] = path
        output_matches[path] = path
        alias = get(v, "alias", nothing)
        isnothing(alias) || (output_matches[alias] = path)
    end
    controls = [
        APIDict(
            "kind" => widget_kind(p),
            "role" => widget_role(p),
            "system" => p["system"],
            "name" => p["name"],
            "path" => p["config_path"],
            "config_path" => p["config_path"],
            "declared_path" => p["declared_path"],
            "accepted_config_paths" => p["accepted_config_paths"],
            "alias" => get(p, "alias", nothing),
            "label" => widget_short_label(p),
            "description" => get(p, "description", ""),
            "unit" => p["unit"],
            "default" => p["default"]["value"],
            "value_type" => p["default"]["type"],
            "state" => p["state"],
            "min" => get(p["tags"], "min", nothing),
            "max" => get(p["tags"], "max", nothing),
            "step" => widget_step(p),
            "accept" => widget_role(p) == "table" ? ".csv,text/csv" : nothing,
            "columns" => [],
            "source" => "dsl",
        )
        for p in d["parameters"]
    ]
    table_paths = Set(String(c["path"]) for c in controls if c["role"] == "table")
    for table in d["tables"]
        path = table["config_path"]
        if path in table_paths
            control = controls[findfirst(c -> c["role"] == "table" && c["path"] == path, controls)]
            isempty(control["columns"]) && (control["columns"] = table["consumers"])
            continue
        end
        push!(table_paths, path)
        push!(controls, APIDict(
            "kind" => "file",
            "role" => "table",
            "system" => table["system"],
            "name" => table["name"],
            "path" => path,
            "config_path" => path,
            "declared_path" => get(table, "declared_path", path),
            "accepted_config_paths" => table["accepted_config_paths"],
            "alias" => get(table, "alias", nothing),
            "label" => widget_short_label(table),
            "description" => get(table, "description", ""),
            "unit" => nothing,
            "default" => nothing,
            "value_type" => "TableInput",
            "state" => table["state"],
            "min" => nothing,
            "max" => nothing,
            "step" => nothing,
            "accept" => ".csv,text/csv",
            "columns" => table["consumers"],
            "source" => "dsl",
        ))
    end
    apply_table_input_ui!(controls, get(ui_, "table_inputs", []))
    filter!(c -> c["path"] != "Clock.step", controls)
    push!(controls, api_clock_step_control(S, config))
    output_options = [output_path(v) for v in outputs]
    default_x = "time"
    default_y_candidates = filter(!=(default_x), output_options)
    default_y = isempty(default_y_candidates) ? [] : [first(default_y_candidates)]
    panels = [normalize_widget_panel(p, output_matches) for p in get(ui_, "panels", [default_panel(default_x, default_y)])]
    sweeps = get(ui_, "sweeps", [])
    payload = APIDict(
        "title" => get(ui_, "title", string(d["model"]["name"], " Dashboard")),
        "contract" => d["contract"],
        "model" => d["model"],
        "systems" => d["systems"],
        "controls" => controls,
        "outputs" => outputs,
        "tables" => d["tables"],
        "simulation" => APIDict(
            "stop" => get(ui_, "stop", APIDict("value" => 5, "unit" => "hr")),
            "snap" => get(ui_, "snap", nothing),
        ),
        "visualize" => APIDict(
            "x" => APIDict("options" => output_options, "default" => default_x),
            "y" => APIDict("options" => output_options, "default" => default_y),
            "kind" => APIDict("options" => ["line", "scatter", "scatterline", "step"], "default" => "line"),
            "backend" => APIDict("options" => ["Gadfly"], "default" => "Gadfly"),
        ),
        "panels" => panels,
    )
    isempty(sweeps) || (payload["sweeps"] = sweeps)
    external_inputs = get(ui_, "external_inputs", [])
    isempty(external_inputs) || (payload["external_inputs"] = external_inputs)
    external_sources = get(ui_, "external_sources", [])
    isempty(external_sources) || (payload["external_sources"] = external_sources)
    payload
end

widget_short_label(item) = begin
    path = get(item, "declared_path", get(item, "config_path", get(item, "name", "")))
    last(split(string(path), '.'))
end

apply_table_input_ui!(controls, specifications) = begin
    specs = [stringkeydict(spec) for spec in specifications]
    for spec in specs
        path = get(spec, "path", get(spec, "config_path", nothing))
        isnothing(path) && error("table input specification requires `path`")
        control = findfirst(c -> c["role"] == "table" && path in get(c, "accepted_config_paths", [c["path"]]), controls)
        isnothing(control) && error("table input specification does not match a provided table: $path")
        entry = controls[control]
        for key in ("label", "description", "accept", "columns", "default_filename")
            haskey(spec, key) && (entry[key] = spec[key])
        end
    end
    controls
end

api_clock_context(S::Type{<:System}) = begin
    contexts = api_system_contexts(S; exclude=())
    context = findfirst(ctx -> ctx.type <: Clock, contexts)
    isnothing(context) ? (; type=Clock) : contexts[context]
end

api_clock_step_value(S::Type{<:System}, config) = begin
    clock = api_clock_context(S)
    configured = configure(parameters(S; recursive=true, exclude=()), config)
    fields = get(configured, namefor(clock.type), nothing)
    isnothing(fields) ? unitfy(1, timeunit(clock.type)) : get(fields, :step, unitfy(1, timeunit(clock.type)))
end

api_time_output(S::Type{<:System}, config) = begin
    clock = api_clock_context(S)
    variable = only(filter(v -> v.name == :time, geninfos(clock.type)))
    APIDict(
        "system" => string(namefor(clock.type)),
        "name" => "time",
        "declared_path" => "$(namefor(clock.type)).time",
        "target_path" => "time",
        "alias" => nothing,
        "description" => "Simulation time generated by the model clock.",
        "state" => "advance",
        "type" => api_variable_type(variable),
        "unit" => encode_api_unit(timeunit(clock.type)),
        "tags" => APIDict(),
        "dependencies" => String[],
        "role" => "output",
        "source" => "runtime",
    )
end

api_clock_step_control(S::Type{<:System}, config) = begin
    clock = api_clock_context(S)
    value = api_clock_step_value(S, config)
    encoded = encode_api_value(value)
    APIDict(
        "kind" => "number",
        "role" => "parameter",
        "system" => string(namefor(clock.type)),
        "name" => "step",
        "path" => "Clock.step",
        "config_path" => "Clock.step",
        "declared_path" => "Clock.step",
        "accepted_config_paths" => ["Clock.step"],
        "alias" => nothing,
        "label" => "step",
        "description" => "Simulation time step exposed as a runtime configuration control.",
        "unit" => encoded["unit"],
        "default" => encoded["value"],
        "value_type" => encoded["type"],
        "state" => "preserve",
        "min" => nothing,
        "max" => nothing,
        "step" => 1,
        "accept" => nothing,
        "columns" => [],
        "source" => "runtime",
    )
end

"""
    external_table_payload(source::AbstractDict, response::AbstractDict)

Convert a dashboard external-source mapping and provider JSON response into
the CSV table payload accepted by `normalize_request`. This is the server-side,
testable counterpart of the browser dashboard's external weather fetch path.
The mapping follows the `external_sources` entries returned by
[`widget_payload`](@ref), including `time_path`, `value_path`, `target`, and
`columns`.
"""
external_table_payload(source::AbstractDict, response::AbstractDict) = begin
    s = stringkeydict(source)
    r = stringkeydict(response)
    time = get_api_path(r, get(s, "time_path", "daily.time"))
    values = get_api_path(r, get(s, "value_path", "daily.temperature_2m_mean"))
    isnothing(time) && error("external source response is missing time path")
    isnothing(values) && error("external source response is missing value path")
    length(time) == length(values) || error("external source time/value lengths do not match")
    isempty(values) && error("external source response has no rows")

    columns = get(s, "columns", [
        APIDict("name" => "index", "type" => "Float64", "unit" => "d"),
        APIDict("name" => "tavg", "type" => "Float64", "unit" => "°C"),
    ])
    length(columns) >= 2 || error("external source columns must include index and value columns")
    cols = [stringkeydict(c) for c in columns]
    index_name = get(cols[1], "name", "index")
    value_name = get(cols[2], "name", "tavg")
    index_type = get(cols[1], "type", nothing)
    temporal_index = index_type in ("Date", "DateTime", "ZonedDateTime")
    rows = [join(api_csv_cell.((index_name, value_name)), ",")]
    for (i, value) in enumerate(values)
        index = temporal_index ? time[i] : i - 1
        push!(rows, join(api_csv_cell.((index, value)), ","))
    end
    APIDict(
        "type" => "CSV",
        "filename" => "$(get(s, "name", "external")).csv",
        "content" => join(rows, "\n") * "\n",
        "columns" => cols,
        "source" => APIDict(
            "name" => get(s, "name", nothing),
            "target" => get(s, "target", nothing),
            "time_path" => get(s, "time_path", nothing),
            "value_path" => get(s, "value_path", nothing),
        ),
        "summary" => APIDict(
            "nrow" => length(values),
            "first_time" => first(time),
            "last_time" => last(time),
        ),
    )
end

"""
    normalize_request(S::Type{<:System}, request::AbstractDict)

Normalize a JSON-compatible simulation request into arguments accepted by
`simulate`. This is an implementation detail of the HTTP API, kept as a
separate function so request parsing can be tested without starting a server.
"""
normalize_request(S::Type{<:System}, request::AbstractDict) = begin
    r = stringkeydict(request)
    APIDict(
        "config" => parse_api_request_config(r),
        "configs" => parse_api_configs(get(r, "configs", nothing)),
        "index" => parse_api_names(get(r, "index", nothing)),
        "target" => parse_api_names(get(r, "target", nothing)),
        "stop" => parse_api_value(get(r, "stop", nothing)),
        "snap" => parse_api_value(get(r, "snap", nothing)),
        "base" => parse_api_name(get(r, "base", nothing)),
        "meta" => parse_api_names(get(r, "meta", nothing)),
        "options" => parse_api_options(get(r, "options", nothing)),
        "seed" => parse_api_value(get(r, "seed", nothing)),
        "nounit" => parse_api_bool(get(r, "nounit", nothing)),
        "long" => parse_api_bool(get(r, "long", nothing)),
        "api_options" => stringkeydict(get(r, "api_options", APIDict())),
    )
end

has_default_config(config) = !(config === nothing || config === () || (config isa AbstractDict && isempty(config)) || (config isa AbstractArray && isempty(config)))

function add_config_kwargs!(kwargs, normalized, default_config)
    request_config = normalized["config"]
    request_configs = normalized["configs"]
    base_config = if !isnothing(request_config)
        api_effective_config(default_config, request_config)
    elseif has_default_config(default_config)
        default_config
    else
        nothing
    end
    if !isnothing(request_configs)
        kwargs[:configs] = isnothing(base_config) ? request_configs :
            [configure(base_config, variant) for variant in request_configs]
    elseif !isnothing(base_config)
        kwargs[:config] = base_config
    end
    return kwargs
end

api_effective_config(default_config, request_config) =
    has_default_config(default_config) ? configure(default_config, request_config) : request_config

function add_operation_kwargs!(kwargs, normalized, keys)
    for key in keys
        value = normalized[key]
        api_keyword_present(value) && (kwargs[Symbol(key)] = value)
    end
    return kwargs
end

api_keyword_present(value) =
    !(isnothing(value) || value === () || (value isa AbstractDict && isempty(value)) ||
      (value isa NamedTuple && isempty(value)))

function add_options_kwargs!(kwargs, default_options, request_options)
    options = api_effective_options(default_options, request_options)
    api_keyword_present(options) && (kwargs[:options] = options)
    return kwargs
end

api_effective_options(default_options, request_options) = begin
    d = parse_api_options(default_options)
    r = parse_api_options(request_options)
    if api_keyword_present(d) && api_keyword_present(r) && d isa NamedTuple && r isa NamedTuple
        merge(d, r)
    elseif api_keyword_present(r)
        r
    else
        d
    end
end

"""
    simulate_payload(S::Type{<:System}, request::AbstractDict)

Parse an API request, run `simulate(S; ...)`, and return a JSON-compatible table
payload with column metadata separated from row values. HTTP handlers use this
as their simulation backend.
"""
simulate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=()) = begin
    normalized = normalize_request(S, request)
    kwargs = Dict{Symbol,Any}()
    add_config_kwargs!(kwargs, normalized, config)
    add_operation_kwargs!(kwargs, normalized, ("index", "target", "stop", "snap", "base", "meta", "seed", "nounit", "long"))
    add_options_kwargs!(kwargs, options, normalized["options"])
    api_options = stringkeydict(get(normalized, "api_options", APIDict()))
    verbose = get(api_options, "verbose", false)
    elapsed = @elapsed df = simulate(S; kwargs..., verbose)
    table_payload(df; model=string(nameof(S)), elapsed_ms=round(Int, elapsed * 1000))
end

"""
    evaluate_payload(S::Type{<:System}, request::AbstractDict)

Parse an API request, run `evaluate(S, observed; ...)`, and return a
JSON-compatible metric payload. The observation table uses the same CSV/DataFrame
encoding as configuration values supplied to `provide` parameters.
"""
evaluate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=()) = begin
    r = stringkeydict(request)
    obs = parse_api_observations(r)
    normalized = normalize_request(S, r)
    kwargs = Dict{Symbol,Any}()
    add_config_kwargs!(kwargs, normalized, config)
    add_operation_kwargs!(kwargs, normalized, ("index", "target", "stop", "snap", "base", "meta", "seed"))
    add_options_kwargs!(kwargs, options, normalized["options"])
    metric = parse_api_metric(get(r, "metric", nothing))
    isnothing(metric) || (kwargs[:metric] = metric)

    elapsed = @elapsed value = evaluate(S, obs; kwargs...)
    APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "model" => string(nameof(S)),
        "operation" => "evaluate",
        "metric" => string(get(kwargs, :metric, :rmse)),
        "target" => encode_api_plain(get(normalized, "target", nothing)),
        "value" => encode_api_result(value),
        "summary" => APIDict(
            "nobs" => nrow(obs),
            "elapsed_ms" => round(Int, elapsed * 1000),
        ),
    )
end

"""
    calibrate_payload(S::Type{<:System}, request::AbstractDict)

Parse an API request, run `calibrate(S, observed; ...)`, and return the calibrated
configuration as a unit-aware JSON object. Parameter bounds can be supplied as a
nested object or as a list of `system`, `name`, `lower`, and `upper` entries.
"""
calibrate_payload(S::Type{<:System}, request::AbstractDict; config=(), options=()) = begin
    r = stringkeydict(request)
    obs = parse_api_observations(r)
    normalized = normalize_request(S, r)
    kwargs = Dict{Symbol,Any}()
    add_config_kwargs!(kwargs, normalized, config)
    add_operation_kwargs!(kwargs, normalized, ("index", "target", "stop", "snap", "base", "meta", "seed"))
    add_options_kwargs!(kwargs, options, normalized["options"])
    kwargs[:parameters] = parse_api_parameters(get(r, "parameters", nothing))
    metric = parse_api_metric(get(r, "metric", nothing))
    isnothing(metric) || (kwargs[:metric] = metric)
    haskey(r, "weight") && (kwargs[:weight] = r["weight"])
    haskey(r, "pareto") && (kwargs[:pareto] = Bool(r["pareto"]))
    optim = parse_api_keywords(get(r, "optim", nothing))
    isempty(optim) || (kwargs[:optim] = optim)

    elapsed = @elapsed config = calibrate(S, obs; kwargs...)
    APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "model" => string(nameof(S)),
        "operation" => "calibrate",
        "metric" => string(get(kwargs, :metric, :rmse)),
        "target" => encode_api_plain(get(normalized, "target", nothing)),
        "config" => encode_api_config(config),
        "summary" => APIDict(
            "nobs" => nrow(obs),
            "nparameters" => length(parameterkeys(configure(kwargs[:parameters]))),
            "elapsed_ms" => round(Int, elapsed * 1000),
        ),
    )
end

"""
    visualize_payload(S::Type{<:System}, request::AbstractDict)

Run `visualize(S, x, y; ...)` from a JSON-compatible request and return a static
SVG payload. HTTP handlers use this as their visualization backend.
"""
visualize_payload(S::Type{<:System}, request::AbstractDict; config=()) = begin
    r = stringkeydict(request)
    x = parse_api_name(get(r, "x", "time"))
    y = parse_api_names(get(r, "y", get(r, "target", nothing)))
    isnothing(y) && error("visualize payload requires `y` or `target`")

    kwargs = Dict{Symbol,Any}()
    request_config = parse_api_request_config(r)
    if !isnothing(request_config)
        kwargs[:config] = api_effective_config(config, request_config)
    elseif has_default_config(config)
        kwargs[:config] = config
    end
    for key in ("stop", "snap", "base")
        value = key in ("stop", "snap") ? parse_api_value(get(r, key, nothing)) :
                parse_api_name(get(r, key, nothing))
        isnothing(value) || (kwargs[Symbol(key)] = value)
    end
    for key in ("xstep",)
        value = parse_api_step(get(r, key, nothing))
        isnothing(value) || (kwargs[Symbol(key)] = value)
    end
    plotopts = stringkeydict(get(r, "plot", APIDict()))
    haskey(r, "kind") && (plotopts["kind"] = r["kind"])
    plotopts["backend"] = Symbol(get(r, "backend", "Gadfly"))
    for (k, v) in plotopts
        kwargs[Symbol(k)] = if k in ("kind", "backend") && v isa AbstractString
            Symbol(v)
        elseif k == "linestyles" && v isa AbstractVector
            Symbol.(v)
        else
            v
        end
    end

    elapsed = @elapsed p = visualize(S, x, y; kwargs...)
    svg = render_api_svg(p)
    APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "model" => string(nameof(S)),
        "format" => "svg",
        "content_type" => "image/svg+xml",
        "body" => svg,
        "summary" => APIDict("elapsed_ms" => round(Int, elapsed * 1000)),
    )
end

"""
    serve(S::Type{<:System}; host="127.0.0.1", port=8000, config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static, async=false)

Expose existing Cropbox operations for a system through HTTP routes. Metadata
routes publish the model description from [`describe`](@ref) and reusable
request schemas. Operation routes parse JSON payloads and dispatch them to
Cropbox workflows including `simulate`, `visualize`, `evaluate`, and
`calibrate`.

`request_defaults` may contain trusted server-side operation defaults that are
merged before a JSON request. This supports existing-model presets such as a
Julia `snap` function without serializing executable code to the client.
Configuration entries are merged by path so a client entry replaces the
corresponding default while other default entries remain.

Routes:
- `GET /api/model`
- `GET /api/schema`
- `GET /api/openapi`
- `GET /api/docs`
- `POST /api/simulate`
- `POST /api/visualize`
- `POST /api/evaluate`
- `POST /api/calibrate`
- `GET /api/dashboard`
- `GET /`
- `GET /dashboard`

The default call blocks while serving. Set `async=true` to return the HTTP
server object without blocking the calling task. The service has no built-in
authentication or transport encryption; bind to loopback unless it is placed
behind an appropriate production gateway.
"""
serve(S::Type{<:System}; host="127.0.0.1", port=8000, config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static, async=false) = begin
    frontend = dashboard_frontend(dashboard)
    get_cache = api_get_route_cache(S; config, ui)
    handler = request -> begin
        method = String(request.method)
        path = HTTP.URI(String(request.target)).path
        status, content_type, body = if method == "GET" && haskey(get_cache, path)
            get_cache[path]
        else
            route_api_response(S, request; config, options, request_defaults, ui, dashboard=frontend)
        end
        HTTP.Response(status, ["Content-Type" => content_type], body)
    end
    if async
        if port == 0
            listener = Sockets.listen(Sockets.getaddrinfo(host), 0)
            actual_port = Int(Sockets.getsockname(listener)[2])
            server = HTTP.serve!(handler, listener)
            @info "Cropbox API server listening" host port=actual_port model=string(nameof(S))
            server
        else
            server = HTTP.serve!(handler, host, port)
            @info "Cropbox API server listening" host port model=string(nameof(S))
            server
        end
    else
        @info "Cropbox API server listening" host port model=string(nameof(S))
        HTTP.serve(handler, host, port)
    end
end

api_get_route_cache(S::Type{<:System}; config=(), ui=APIDict()) = begin
    description = describe(S; config)
    widgets = widget_payload(S; config, ui, description)
    json_response(value) = (200, "application/json; charset=utf-8", json_body(value))
    widget_response = json_response(widgets)
    APIDict(
        "/api/model" => json_response(description),
        "/api/dashboard" => widget_response,
        "/api/schema" => json_response(api_schema()),
        "/api/openapi" => json_response(api_openapi(api_openapi_examples(description))),
        "/api/docs" => (200, "text/html; charset=utf-8", swagger_ui_html()),
        "/docs" => (200, "text/html; charset=utf-8", swagger_ui_html()),
    )
end

"""
    dashboard(S::Type{<:System}; frontend=:static, kwargs...)

Start the same service as [`serve`](@ref), selecting the browser frontend with
`frontend`. The generated client reads the canonical `/api/dashboard` metadata
route and calls the same operation routes as non-browser clients.

Use `frontend=:static` for the bundled client or `frontend=:none` to expose only
the programming API. A package can subtype `Cropbox.DashboardFrontend` and
implement `Cropbox.dashboard_route_response` without changing the route
contract.
"""
dashboard(S::Type{<:System}; frontend=:static, kwargs...) = serve(S; dashboard=frontend, kwargs...)

table_payload(df::DataFrame; model, elapsed_ms=nothing) = begin
    cols = names(df)
    units = api_column_units(df)
    columns = [
        APIDict(
            "name" => string(name),
            "type" => string(eltype(deunitfy(df[!, name]))),
            "unit" => encode_api_unit(unit),
        )
        for (name, unit) in zip(cols, units)
    ]
    rows = [[encode_api_plain(deunitfy(row[name])) for name in cols] for row in eachrow(df)]
    APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "model" => model,
        "columns" => columns,
        "rows" => rows,
        "summary" => APIDict("nrow" => nrow(df), "elapsed_ms" => elapsed_ms),
    )
end

render_api_svg(p) = sprint(show, MIME("text/html"), p)

parameter_info_map(S::Type{<:System}; recursive=true, exclude=(Context,), scope=nothing) = begin
    info = Dict{Tuple{Symbol,Symbol},Any}()
    for ctx in api_system_contexts(S; recursive, exclude)
        collect_parameter_info!(info, ctx.type; scope)
    end
    info
end

api_parameter_unit_map(contexts) = begin
    units = Dict{Tuple{Symbol,Symbol},Any}()
    for ctx in contexts, v in geninfos(ctx.type)
        unit = api_variable_unit(ctx.type, v.name)
        units[(namefor(ctx.type), v.name)] = unit
        isnothing(v.alias) || (units[(namefor(ctx.type), v.alias)] = unit)
    end
    units
end

collect_parameter_info!(info, S::Type{<:System}; scope=nothing) = begin
    for v in [n.info for n in dependency(S).N]
        info[(namefor(S), v.name)] = v
        isnothing(v.alias) || (info[(namefor(S), v.alias)] = v)
    end
    info
end

api_variable_entries(ctx) = begin
    T = ctx.type
    [
        api_variable_entry(ctx, v)
        for v in geninfos(T)
        if api_variable_projected(v)
    ]
end

api_variable_projected(v) = !isnothing(v.state) && v.state != :Provide

api_variable_entry(ctx, v) = begin
    system = namefor(ctx.type)
    name = v.name
    APIDict(
        "system" => string(system),
        "name" => string(name),
        "declared_path" => api_config_path_for(v.system, v, name),
        "accepted_config_paths" => api_accepted_config_paths(system, v, name),
        "target_path" => api_target_path(ctx.access_path, name),
        "alias" => isnothing(v.alias) ? nothing : string(v.alias),
        "description" => strip(v.docstring),
        "state" => api_state_name(v.state),
        "type" => api_variable_type(v),
        "unit" => encode_api_unit(api_variable_unit(ctx.type, name)),
        "tags" => api_variable_tags(v),
        "dependencies" => api_variable_dependencies(v),
        "role" => api_variable_role(v),
    )
end

api_table_entries(ctx) = begin
    providers = filter(v -> v.state == :Provide, geninfos(ctx.type))
    isempty(providers) && return APIDict[]
    drives = filter(v -> v.state == :Drive, geninfos(ctx.type))
    [api_table_entry(ctx, provider, drives) for provider in providers]
end

api_table_entry(ctx, provider, drives) = begin
    system = namefor(ctx.type)
    provider_name = provider.name
    consumers = [
        api_table_consumer(ctx, drive)
        for drive in drives
        if api_tag_symbol(gettag(drive, :from, nothing)) == provider_name
    ]
    APIDict(
        "system" => string(system),
        "name" => string(provider_name),
        "config_path" => api_config_path_for(system, provider, provider_name),
        "declared_path" => api_config_path_for(provider.system, provider, provider_name),
        "accepted_config_paths" => api_accepted_config_paths(system, provider, provider_name),
        "target_path" => api_target_path(ctx.access_path, provider_name),
        "description" => strip(provider.docstring),
        "state" => api_state_name(provider.state),
        "index" => api_tag_encoded(gettag(provider, :index, QuoteNode(:index))),
        "tags" => api_variable_tags(provider),
        "consumers" => consumers,
        "role" => "table",
    )
end

api_table_consumer(ctx, drive) = APIDict(
    "variable" => api_target_path(ctx.access_path, drive.name),
    "name" => string(drive.name),
    "column" => api_tag_encoded(gettag(drive, :by, QuoteNode(drive.name))),
    "unit" => encode_api_unit(api_variable_unit(ctx.type, drive.name)),
)

api_config_path(system, name) = "$(system).$(name)"
api_config_key(system, name) = uncanonicalname(name, system)
api_config_path_for(system, name) = api_config_path(system, api_config_key(system, name))
api_config_path_for(system, v, name) = api_config_path(system, api_config_key(system, name))
api_target_path(access_path, name) = isempty(access_path) ? string(name) : "$(access_path).$(name)"
api_config_scopes(system, v) = unique(string.([system, v.system]))
api_accepted_config_paths(system, v, name) = unique([
    api_config_path_for(system, v, name),
    api_config_path_for(v.system, v, name),
])

api_variable_unit(T::Type{<:System}, name) = get(fieldunits(T), name, nothing)

api_variable_type(v) = begin
    raw = gettag(v, :_type, nothing)
    isnothing(raw) ? nothing : api_public_type_name(raw)
end

api_public_type_name(raw::QuoteNode) = api_public_type_name(raw.value)
api_public_type_name(raw::Expr) = begin
    raw.head in (:escape, :quote) && length(raw.args) == 1 &&
        return api_public_type_name(only(raw.args))
    raw.head == :. && return api_public_type_name(last(raw.args))
    if raw.head == :call && length(raw.args) == 2 && api_public_type_name(first(raw.args)) == "typefor"
        return api_public_type_name(last(raw.args))
    end
    if raw.head == :curly && !isempty(raw.args)
        name = api_public_type_name(first(raw.args))
        parameters = join(api_public_type_name.(raw.args[2:end]), ", ")
        return "$(name){$(parameters)}"
    end
    string(raw)
end
api_public_type_name(raw) = string(raw)

api_variable_dependencies(v) = sort(string.(uncanonicalname.(collect(extract(v; tag=false)))))

api_variable_role(v) = begin
    v.state == :Provide && return "table"
    istag(v, :parameter) && return "parameter"
    v.state in (:Track, :Accumulate, :Capture, :Drive, :Preserve, :Flag, :Bisect, :Solve) && return "output"
    "internal"
end

api_variable_tags(v) = begin
    tags = APIDict()
    for (tag, raw) in v.tags
        tag in API_PUBLIC_VARIABLE_TAGS || continue
        encoded = api_tag_encoded(raw)
        tag == :optional && encoded === false && continue
        tags[string(tag)] = encoded
    end
    tags
end

api_parameter_tags(v) = begin
    tags = APIDict()
    for tag in (:min, :max, :optional)
        value = api_tag_value(v, tag)
        isnothing(value) || (tags[string(tag)] = encode_api_plain(value))
    end
    tags
end

api_tag_value(v, tag) = begin
    try
        raw = gettag(v, tag)
        raw isa QuoteNode && return raw.value
        raw isa Union{Number,Bool,AbstractString,Symbol} && return raw
        value(raw)
    catch
        nothing
    end
end

api_tag_symbol(raw::QuoteNode) = raw.value isa Symbol ? raw.value : nothing
api_tag_symbol(raw::Symbol) = raw
api_tag_symbol(raw) = nothing

api_tag_encoded(raw::QuoteNode) = api_tag_encoded(raw.value)
api_tag_encoded(raw::Symbol) = string(uncanonicalname(raw))
api_tag_encoded(raw::Union{Number,Bool,AbstractString}) = encode_api_plain(raw)
api_tag_encoded(raw::Nothing) = nothing
api_tag_encoded(raw::AbstractVector) = api_tag_encoded.(raw)
api_tag_encoded(raw) = begin
    value = api_tag_value_from_raw(raw)
    value === raw ? string(raw) : api_tag_encoded(value)
end

api_tag_value_from_raw(raw) = begin
    try
        value(raw)
    catch
        raw
    end
end

default_panel(x, y) = APIDict(
    "title" => "Panel 1",
    "x" => x,
    "y" => y,
    "kind" => "line",
)

normalize_widget_panel(panel, output_matches) = begin
    p = stringkeydict(panel)
    haskey(p, "x") && (p["x"] = normalize_widget_output_path(p["x"], output_matches))
    haskey(p, "y") && (p["y"] = normalize_widget_output_path(p["y"], output_matches))
    p
end

normalize_widget_output_path(value::AbstractString, output_matches) = get(output_matches, value, value)
normalize_widget_output_path(value::AbstractVector, output_matches) = [normalize_widget_output_path(v, output_matches) for v in value]
normalize_widget_output_path(value, output_matches) = value

widget_kind(parameter) = begin
    default = parameter["default"]
    type = get(default, "type", "")
    if parameter["state"] == "provide"
        "file"
    elseif occursin("Bool", type)
        "checkbox"
    elseif occursin(r"^(Int|UInt|Float)", type) || !isnothing(parameter["unit"])
        "number"
    else
        "text"
    end
end

widget_role(parameter) = parameter["state"] == "provide" ? "table" : "parameter"

widget_step(parameter) = begin
    type = get(parameter["default"], "type", "")
    if occursin(r"^(Int|UInt)", type)
        1
    elseif widget_kind(parameter) == "number"
        0.1
    else
        nothing
    end
end

api_column_units(df::DataFrame) = [
    try
        unittype(df[!, name])
    catch
        nothing
    end
    for name in names(df)
]

encode_api_config(config) = begin
    c = configure(config)
    APIDict(
        string(system) => APIDict(string(name) => encode_api_value(value) for (name, value) in fields)
        for (system, fields) in c
    )
end

encode_api_value(value, unit=nothing) = begin
    u = isnothing(unit) ? api_value_unit(value) : unit
    raw = isnothing(unit) ? deunitfy(value) : deunitfy(value, unit)
    encoded = encode_api_plain(raw)
    APIDict(
        "value" => encoded,
        "type" => value isa Quantity ? string(typeof(encoded)) : api_value_type(value),
        "unit" => encode_api_unit(u),
    )
end

api_value_type(value) = value isa Quantity ? string(typeof(deunitfy(value))) : string(typeof(value))
api_value_unit(value) = try
    unittype(value)
catch
    nothing
end
encode_api_unit(unit) = hasunit(unit) ? unitlabel(unit) : nothing
encode_api_plain(value::Symbol) = string(value)
encode_api_plain(value::ZonedDateTime) = string(value)
encode_api_plain(value::DateTime) = string(value)
encode_api_plain(value::Date) = string(value)
encode_api_plain(value::Rational) = float(value)
encode_api_plain(value::AbstractFloat) = isfinite(value) ? value : nothing
encode_api_plain(value::AbstractVector) = encode_api_plain.(value)
encode_api_plain(value) = value

parse_api_request_config(request::AbstractDict) = begin
    r = stringkeydict(request)
    has_nested = haskey(r, "config")
    has_entries = haskey(r, "config_entries")
    if !has_nested && !has_entries
        return nothing
    end

    configs = Any[]
    if has_nested
        nested = parse_api_config(r["config"])
        isnothing(nested) || push!(configs, nested)
    end
    if has_entries
        entries = parse_api_config_entries(r["config_entries"])
        isnothing(entries) || push!(configs, entries)
    end
    isempty(configs) ? nothing : configure(configs...)
end

parse_api_configs(::Nothing) = nothing
parse_api_configs(configs) = [parse_api_config_object(c) for c in configs]

parse_api_config_object(config::AbstractDict) = begin
    c = stringkeydict(config)
    haskey(c, "config") || haskey(c, "config_entries") ? parse_api_request_config(c) : parse_api_config(c)
end
parse_api_config_object(config) = parse_api_config(config)

parse_api_config(::Nothing) = nothing
parse_api_config(config) = begin
    c = stringkeydict(config)
    systems = OrderedDict{Symbol,Any}()
    for (system, fields) in c
        f = stringkeydict(fields)
        values = OrderedDict{Symbol,Any}(Symbol(name) => parse_api_value(value) for (name, value) in f)
        systems[Symbol(system)] = values
    end
    configure(systems)
end

parse_api_config_entries(::Nothing) = nothing
parse_api_config_entries(entries::AbstractVector) = begin
    pairs = parse_api_config_entry.(entries)
    isempty(pairs) ? configure() : configure(pairs...)
end
parse_api_config_entries(entries::AbstractDict) = begin
    e = stringkeydict(entries)
    if haskey(e, "path") || (haskey(e, "system") && haskey(e, "name"))
        return configure(parse_api_config_entry(e))
    end
    pairs = [String(path) => parse_api_value(value) for (path, value) in e]
    isempty(pairs) ? configure() : configure(pairs...)
end
parse_api_config_entries(entries) = error("config_entries must be an object or array")

parse_api_config_entry(raw) = begin
    entry = stringkeydict(raw)
    path = if haskey(entry, "path")
        String(entry["path"])
    elseif haskey(entry, "system") && haskey(entry, "name")
        "$(entry["system"]).$(entry["name"])"
    else
        error("config entry requires `path` or `system` and `name`")
    end
    haskey(entry, "value") || error("config entry requires `value`")
    path => parse_api_value(entry["value"])
end

parse_api_names(::Nothing) = nothing
parse_api_names(value::AbstractString) = parse_api_name(value)
parse_api_names(value::AbstractVector) = parse_api_name_entry.(value)
parse_api_names(value::AbstractDict) = parse_api_name_mapping(value)
parse_api_names(value) = value

parse_api_name_entry(value::AbstractDict) = begin
    entry = stringkeydict(value)
    if haskey(entry, "name")
        path = get(entry, "path", get(entry, "target", get(entry, "value", nothing)))
        isnothing(path) && error("name mapping requires `path`, `target`, or `value`")
        Symbol(entry["name"]) => parse_api_name(path)
    else
        error("name mapping entry requires `name`")
    end
end
parse_api_name_entry(value) = parse_api_name(value)

parse_api_name_mapping(value::AbstractDict) = begin
    entries = stringkeydict(value)
    [Symbol(name) => parse_api_name(path) for (name, path) in entries]
end

parse_api_name(::Nothing) = nothing
parse_api_name(value::AbstractString) = occursin(".", value) ? value : Symbol(value)
parse_api_name(value) = value

parse_api_step(::Nothing) = nothing
parse_api_step(value::AbstractDict) = begin
    v = stringkeydict(value)
    system, name = parse_api_step_target(v)
    values = if haskey(v, "values")
        parse_api_value.(v["values"])
    else
        start = parse_api_value(get(v, "start", get(v, "min", nothing)))
        stop = parse_api_value(get(v, "stop", get(v, "max", nothing)))
        step = parse_api_value(get(v, "step", nothing))
        unit = get(v, "unit", nothing)
        if api_unit_specified(unit)
            u = parse_api_unit(unit)
            start = unitfy(start, u)
            stop = unitfy(stop, u)
            step = unitfy(step, Unitful.absoluteunit(u))
        end
        start:step:stop
    end
    system => name => values
end
parse_api_step(value) = value

parse_api_step_target(v) = begin
    if haskey(v, "path")
        parts = split(v["path"], ".")
        length(parts) == 2 || error("step path must be System.parameter")
        Symbol(parts[1]), Symbol(parts[2])
    else
        Symbol(v["system"]), Symbol(v["name"])
    end
end

parse_api_value(::Nothing) = nothing
parse_api_value(value::Union{Number,Bool}) = value
parse_api_value(value::AbstractString) = value
parse_api_value(value::AbstractDict) = begin
    v = stringkeydict(value)
    kind = get(v, "type", nothing)
    if kind == "DataFrame"
        return parse_api_table(v)
    elseif kind == "CSV"
        return parse_api_csv(v)
    end
    raw = get(v, "value", nothing)
    parsed = parse_api_typed_value(raw, kind, v)
    unit = get(v, "unit", nothing)
    api_unit_specified(unit) ? unitfy(parsed, parse_api_unit(unit)) : parsed
end
parse_api_value(value) = value

parse_api_observations(r::AbstractDict) = begin
    obs = get(r, "observed", get(r, "obs", nothing))
    isnothing(obs) && error("evaluate/calibrate payload requires `observed` or `obs`")
    df = parse_api_value(obs)
    df isa DataFrame || error("`observed` must be a CSV or DataFrame table payload")
    df
end

parse_api_metric(::Nothing) = nothing
parse_api_metric(value::AbstractString) = Symbol(value)
parse_api_metric(value::Symbol) = value
parse_api_metric(value) = value

encode_api_result(value::Tuple) = [encode_api_value(v) for v in value]
encode_api_result(value) = encode_api_value(value)

parse_api_parameters(::Nothing) = error("calibrate payload requires `parameters`")
parse_api_parameters(value::AbstractVector) = begin
    systems = OrderedDict{Symbol,Any}()
    for raw in value
        entry = stringkeydict(raw)
        system, name = parse_api_step_target(entry)
        fields = get!(systems, system, OrderedDict{Symbol,Any}())
        fields[name] = parse_api_parameter_range(entry)
    end
    configure(systems)
end
parse_api_parameters(value::AbstractDict) = begin
    v = stringkeydict(value)
    if haskey(v, "path") || (haskey(v, "system") && haskey(v, "name"))
        parse_api_parameters([v])
    else
        systems = OrderedDict{Symbol,Any}()
        for (system, fields0) in v
            fields = OrderedDict{Symbol,Any}()
            for (name, range) in stringkeydict(fields0)
                fields[Symbol(name)] = parse_api_parameter_range(range)
            end
            systems[Symbol(system)] = fields
        end
        configure(systems)
    end
end
parse_api_parameters(value) = value

parse_api_parameter_range(value::AbstractDict) = begin
    v = stringkeydict(value)
    lower = parse_api_value(get(v, "lower", get(v, "min", nothing)))
    upper = parse_api_value(get(v, "upper", get(v, "max", nothing)))
    if isnothing(lower) || isnothing(upper)
        error("parameter range requires lower/upper or min/max bounds")
    end
    unit = get(v, "unit", nothing)
    if api_unit_specified(unit)
        u = parse_api_unit(unit)
        lower = lower isa Quantity ? lower : unitfy(lower, u)
        upper = upper isa Quantity ? upper : unitfy(upper, u)
    end
    (lower, upper)
end
parse_api_parameter_range(value::AbstractVector) = begin
    length(value) == 2 || error("parameter range vector must contain two bounds")
    (parse_api_value(value[1]), parse_api_value(value[2]))
end
parse_api_parameter_range(value) = error("unsupported parameter range: $value")

parse_api_keywords(::Nothing) = Dict{Symbol,Any}()
parse_api_keywords(value::AbstractDict) = begin
    Dict{Symbol,Any}(Symbol(k) => parse_api_keyword_value(k, v) for (k, v) in stringkeydict(value))
end
parse_api_keywords(value) = value

parse_api_options(::Nothing) = ()
parse_api_options(value::NamedTuple) = value
parse_api_options(value::AbstractDict) = api_namedtuple(parse_api_keywords(value))
parse_api_options(value) = value

api_namedtuple(dict::AbstractDict) = begin
    pairs = collect(dict)
    names = Tuple(first.(pairs))
    values = Tuple(last.(pairs))
    NamedTuple{names}(values)
end

parse_api_bool(::Nothing) = nothing
parse_api_bool(value::Bool) = value
parse_api_bool(value::AbstractString) = begin
    lower = lowercase(value)
    lower in ("true", "1", "yes", "on") && return true
    lower in ("false", "0", "no", "off") && return false
    error("invalid boolean value: $value")
end
parse_api_bool(value::Number) = !iszero(value)
parse_api_bool(value) = Bool(value)

parse_api_keyword_value(key, value::AbstractString) = key in ("TraceMode", "Method") ? Symbol(value) : value
parse_api_keyword_value(key, value) = parse_api_value(value)

parse_api_typed_value(raw, ::Nothing, meta) = raw
parse_api_typed_value(raw, kind, meta) = begin
    if kind == "Symbol"
        Symbol(raw)
    elseif kind == "DateTime"
        DateTime(raw)
    elseif kind == "Date"
        Date(raw)
    elseif kind == "ZonedDateTime"
        parse_api_zoned_datetime(raw, get(meta, "timezone", nothing))
    elseif kind in ("Int", "Int64")
        Int(raw)
    elseif kind in ("Float64", "Float32", "Float16")
        Float64(raw)
    elseif kind == "Bool"
        Bool(raw)
    else
        raw
    end
end

parse_api_zoned_datetime(value::ZonedDateTime, timezone=nothing) =
    isnothing(timezone) ? value : astimezone(value, TimeZone(timezone))
parse_api_zoned_datetime(value::DateTime, timezone=nothing) =
    isnothing(timezone) ? error("ZonedDateTime values without an offset require `timezone` metadata") :
    ZonedDateTime(value, TimeZone(timezone))
parse_api_zoned_datetime(value, timezone=nothing) = begin
    raw = String(value)
    parsed = try
        ZonedDateTime(raw)
    catch
        nothing
    end
    if !isnothing(parsed)
        return isnothing(timezone) ? parsed : astimezone(parsed, TimeZone(timezone))
    end
    isnothing(timezone) && error("ZonedDateTime value `$raw` requires an offset or `timezone` metadata")
    ZonedDateTime(DateTime(raw), TimeZone(timezone))
end

parse_api_table(v) = begin
    columns = [stringkeydict(c) for c in v["columns"]]
    raw_names = get.(columns, "name", nothing)
    any(isnothing, raw_names) && api_validation_error("Every table column requires a `name`")
    any(api_column_name_has_metadata, raw_names) && api_validation_error(
        "Structured table column names must not contain parenthesized metadata; use the column fields instead"
    )
    names_ = Symbol.(raw_names)
    rows_ = get(v, "rows", [])
    df = DataFrame([name => [row[i] for row in rows_] for (i, name) in enumerate(names_)])
    apply_api_column_metadata!(df, columns)
end

api_column_name_has_metadata(name) = occursin(r"\([^()]+\)\s*$", String(name))

parse_api_csv(v) = begin
    df = CSV.read(IOBuffer(v["content"]), DataFrame)
    implicit = api_csv_header_metadata.(names(df))
    if any(!isnothing, implicit)
        haskey(v, "columns") && api_validation_error(
            "CSV header metadata and the `columns` field cannot be used together"
        )
        apply_api_csv_header_metadata!(df, implicit)
    elseif haskey(v, "columns")
        apply_api_column_metadata!(df, [stringkeydict(c) for c in v["columns"]])
    end
    df
end

const API_CSV_COLUMN_TYPES = Set((
    "Bool", "Date", "DateTime", "Float64", "Int", "Int64", "String",
    "Symbol", "ZonedDateTime",
))

api_csv_header_metadata(name) = begin
    m = match(r"^(.+?)\s*\(([^()]+)\)\s*$", String(name))
    isnothing(m) && return nothing
    column = strip(m.captures[1])
    isempty(column) && api_validation_error("CSV column name cannot be empty")
    annotation = strip(m.captures[2])
    metadata = APIDict("name" => column)
    if startswith(annotation, ":")
        kind = strip(annotation[2:end])
        kind in API_CSV_COLUMN_TYPES || api_validation_error(
            "Unsupported CSV column type `$kind`; use the `columns` field with a supported type"
        )
        metadata["type"] = kind
    else
        try
            parse_api_unit(annotation)
        catch
            api_validation_error(
                "Unsupported CSV column unit `$annotation`; use the `columns` field with a valid unit"
            )
        end
        metadata["unit"] = annotation
    end
    metadata
end

apply_api_csv_header_metadata!(df::DataFrame, metadata) = begin
    converted = filter(!isnothing, metadata)
    targets = [m["name"] for m in converted]
    length(unique(targets)) == length(targets) || api_validation_error(
        "CSV header metadata produces duplicate column names"
    )
    renames = [Symbol(source) => Symbol(meta["name"]) for (source, meta) in zip(names(df), metadata) if !isnothing(meta)]
    DataFrames.rename!(df, renames...)
    apply_api_column_metadata!(df, converted)
end

apply_api_column_metadata!(df::DataFrame, columns) = begin
    for col in columns
        name = Symbol(col["name"])
        name in propertynames(df) || api_validation_error("CSV metadata refers to missing column `$(col["name"])`")
        kind = get(col, "type", nothing)
        if kind == "ZonedDateTime" || haskey(col, "timezone")
            timezone = get(col, "timezone", nothing)
            df[!, name] = [ismissing(x) ? missing : parse_api_zoned_datetime(x, timezone) for x in df[!, name]]
        elseif kind == "DateTime"
            df[!, name] = [ismissing(x) ? missing : x isa DateTime ? x : DateTime(x) for x in df[!, name]]
        elseif kind == "Date"
            df[!, name] = [ismissing(x) ? missing : x isa Date ? x : Date(x) for x in df[!, name]]
        elseif kind == "Symbol"
            df[!, name] = [ismissing(x) ? missing : Symbol(x) for x in df[!, name]]
        end
        if haskey(col, "unit") && api_unit_specified(col["unit"])
            u = parse_api_unit(col["unit"])
            df[!, name] = unitfy(df[!, name], u)
        end
    end
    df
end

api_unit_specified(unit) = !(isnothing(unit) || (unit isa AbstractString && isempty(strip(unit))))

parse_api_unit(unit::AbstractString) = begin
    api_unit_specified(unit) || return nothing
    all(api_unit_character_allowed, unit) || api_validation_error("Invalid characters in unit `$unit`")
    parsed = try
        Unitful.uparse(unit)
    catch
        try
            Unitful.uparse(api_unit_parse_expression(unit))
        catch
            api_validation_error("Unsupported unit `$unit`")
        end
    end
    parsed isa Unitful.Units || api_validation_error("`$unit` does not resolve to a unit")
    parsed
end

api_unit_character_allowed(c) = isletter(c) || isdigit(c) || isspace(c) || c in (
    '°', '%', 'µ', 'μ', '*', '/', '^', '.', '-', '+',
    '⁻', '⁺', '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹',
)

api_unit_parse_expression(unit::AbstractString) = begin
    superscripts = Dict(
        '⁻' => '-', '⁺' => '+', '⁰' => '0', '¹' => '1', '²' => '2',
        '³' => '3', '⁴' => '4', '⁵' => '5', '⁶' => '6', '⁷' => '7',
        '⁸' => '8', '⁹' => '9',
    )
    expanded = replace(unit, r"[⁻⁺⁰¹²³⁴⁵⁶⁷⁸⁹]+" => value -> "^" * join(superscripts[c] for c in value))
    replace(strip(expanded), r"\s+" => "*")
end

get_api_path(object, path) = begin
    value = object
    for key in split(String(path), ".")
        if value isa AbstractDict
            value = get(value, key, nothing)
        else
            return nothing
        end
        isnothing(value) && return nothing
    end
    value
end

api_csv_cell(value::AbstractString) = begin
    if any(occursin.((",", "\"", "\n", "\r"), value))
        "\"" * replace(value, "\"" => "\"\"") * "\""
    else
        value
    end
end
api_csv_cell(value) = value

stringkeydict(object::AbstractDict) = APIDict(string(k) => normalize_json_value(v) for (k, v) in object)
stringkeydict(::Nothing) = APIDict()
normalize_json_value(v::AbstractDict) = stringkeydict(v)
normalize_json_value(v::AbstractVector) = normalize_json_value.(v)
normalize_json_value(v) = v

json_body(payload) = JSON3.write(payload)

route_api_response(S::Type{<:System}, request; config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static) = begin
    try
        method = String(request.method)
        path = HTTP.URI(String(request.target)).path
        body = String(request.body)
        route_api_response(S, method, path, body; config, options, request_defaults, ui, dashboard=dashboard)
    catch e
        500, "application/json; charset=utf-8", json_body(api_error("internal_error", sprint(showerror, e); category="execution"))
    end
end

route_api_response(S::Type{<:System}, method::AbstractString, path::AbstractString, body::AbstractString; config=(), options=(), request_defaults=APIDict(), ui=APIDict(), dashboard=:static) = begin
    try
        frontend = dashboard_frontend(dashboard)
        if method == "GET" && path in dashboard_routes(frontend)
            dashboard_route_response(frontend, S; config, options, ui)
        elseif method == "GET" && path == "/api/model"
            200, "application/json; charset=utf-8", json_body(describe(S; config))
        elseif method == "GET" && path == "/api/dashboard"
            200, "application/json; charset=utf-8", json_body(widget_payload(S; config, ui))
        elseif method == "GET" && path == "/api/schema"
            200, "application/json; charset=utf-8", json_body(api_schema())
        elseif method == "GET" && path == "/api/openapi"
            200, "application/json; charset=utf-8", json_body(api_openapi(S; config))
        elseif method == "GET" && (path == "/api/docs" || path == "/docs")
            200, "text/html; charset=utf-8", swagger_ui_html()
        elseif method == "POST" && path == "/api/simulate"
            payload = apply_request_defaults(request_defaults, parse_json_body(body))
            200, "application/json; charset=utf-8", json_body(simulate_payload(S, payload; config, options))
        elseif method == "POST" && path == "/api/evaluate"
            payload = apply_request_defaults(request_defaults, parse_json_body(body))
            200, "application/json; charset=utf-8", json_body(evaluate_payload(S, payload; config, options))
        elseif method == "POST" && path == "/api/calibrate"
            payload = apply_request_defaults(request_defaults, parse_json_body(body))
            200, "application/json; charset=utf-8", json_body(calibrate_payload(S, payload; config, options))
        elseif method == "POST" && path == "/api/visualize"
            payload = apply_request_defaults(request_defaults, parse_json_body(body))
            200, "application/json; charset=utf-8", json_body(visualize_payload(S, payload; config))
        else
            404, "application/json; charset=utf-8", json_body(api_error("not_found", "No route for $method $path"; path, category="routing"))
        end
    catch e
        api_exception_response(e; path)
    end
end

api_exception_response(e; path=nothing) = begin
    message = sprint(showerror, e)
    if occursin("has no field", lowercase(message))
        return 422, "application/json; charset=utf-8",
            json_body(api_error("invalid_request", "Request references an unknown model variable or path."; path, category="validation"))
    end
    category = api_error_category("invalid_request", message)
    status, code = if category == "syntax"
        400, "invalid_request"
    elseif category == "validation"
        422, "invalid_request"
    else
        500, "execution_failed"
    end
    status, "application/json; charset=utf-8", json_body(api_error(code, message; path, category))
end

api_exception_response(e::APIRequestError; path=nothing) = begin
    status = e.category == "syntax" ? 400 : e.category == "validation" ? 422 : 500
    code = status == 500 ? "execution_failed" : "invalid_request"
    status, "application/json; charset=utf-8", json_body(api_error(code, e.message; path, category=e.category))
end

parse_json_body(body::AbstractString) = JSON3.read(body, Dict{String,Any})

apply_request_defaults(defaults, payload::AbstractDict) = begin
    d = defaults isa NamedTuple ? APIDict(string(k) => v for (k, v) in pairs(defaults)) : stringkeydict(defaults)
    p = stringkeydict(payload)
    merged = merge(d, p)
    if haskey(d, "config_entries") && haskey(p, "config_entries")
        merged["config_entries"] = merge_api_config_entries(d["config_entries"], p["config_entries"])
    end
    merged
end

merge_api_config_entries(defaults::AbstractVector, overrides::AbstractVector) = begin
    merged = collect(defaults)
    positions = Dict{String,Int}()
    for (i, entry) in enumerate(merged)
        path = api_config_entry_path(entry)
        isnothing(path) || (positions[path] = i)
    end
    for entry in overrides
        path = api_config_entry_path(entry)
        if !isnothing(path) && haskey(positions, path)
            merged[positions[path]] = entry
        else
            push!(merged, entry)
            isnothing(path) || (positions[path] = length(merged))
        end
    end
    merged
end
merge_api_config_entries(defaults::AbstractDict, overrides::AbstractDict) =
    merge(stringkeydict(defaults), stringkeydict(overrides))
merge_api_config_entries(defaults, overrides) = overrides

api_config_entry_path(raw) = begin
    entry = stringkeydict(raw)
    haskey(entry, "path") && return String(entry["path"])
    haskey(entry, "system") && haskey(entry, "name") &&
        return "$(entry["system"]).$(entry["name"])"
    nothing
end

api_error(code, message; path=nothing, category=nothing, retryable=false) = begin
    error = APIDict(
        "code" => code,
        "category" => isnothing(category) ? api_error_category(code, message) : category,
        "message" => message,
        "retryable" => retryable,
    )
    isnothing(path) || (error["path"] = path)
    APIDict("status" => "error", "contract_version" => API_CONTRACT_VERSION, "error" => error)
end

api_error_category(code, message) = begin
    code == "not_found" && return "routing"
    code == "internal_error" && return "execution"
    msg = lowercase(String(message))
    if occursin("json", msg) || occursin("eof", msg) || occursin("malformed", msg)
        "syntax"
    elseif occursin("unit", msg) || occursin("observed", msg) || occursin("parameter", msg) ||
           occursin("range", msg) || occursin("bound", msg) || occursin("requires", msg) ||
           occursin("missing", msg) || occursin("unsupported", msg)
        "validation"
    else
        "execution"
    end
end

api_schema() = APIDict(
    "\$schema" => "https://json-schema.org/draft/2020-12/schema",
    "title" => "Cropbox Web API",
    "contract_version" => API_CONTRACT_VERSION,
    "contract" => api_contract_metadata(),
    "description" => "Schema fragments for Cropbox model metadata, simulation, visualization, evaluation, and calibration payloads.",
    "error_taxonomy" => [
        APIDict("category" => "syntax", "boundary" => "JSON body parsing and basic payload decoding"),
        APIDict("category" => "validation", "boundary" => "units, table inputs, required fields, variable names, and parameter bounds"),
        APIDict("category" => "execution", "boundary" => "Cropbox simulation, visualization, evaluation, calibration, and rendering calls"),
        APIDict("category" => "routing", "boundary" => "HTTP method and path dispatch"),
    ],
    "routes" => [
        APIDict("method" => "GET", "path" => "/api/model", "response" => "ModelDescription"),
        APIDict("method" => "GET", "path" => "/api/dashboard", "response" => "WidgetPayload"),
        APIDict("method" => "GET", "path" => "/api/schema", "response" => "JSONSchemaFragments"),
        APIDict("method" => "GET", "path" => "/api/openapi", "response" => "OpenAPI"),
        APIDict("method" => "GET", "path" => "/api/docs", "response" => "SwaggerUI"),
        APIDict("method" => "POST", "path" => "/api/simulate", "request" => "SimulationRequest", "response" => "SimulationResponse"),
        APIDict("method" => "POST", "path" => "/api/visualize", "request" => "VisualizationRequest", "response" => "VisualizationResponse"),
        APIDict("method" => "POST", "path" => "/api/evaluate", "request" => "EvaluationRequest", "response" => "EvaluationResponse"),
        APIDict("method" => "POST", "path" => "/api/calibrate", "request" => "CalibrationRequest", "response" => "CalibrationResponse"),
    ],
    "definitions" => APIDict(
        "SystemDescription" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "name" => APIDict("type" => "string"),
                "module" => APIDict("type" => "string"),
                "root" => APIDict("type" => "boolean"),
                "access_path" => APIDict("type" => "string"),
            ),
            "required" => ["name", "module", "root", "access_path"],
        ),
        "VariableDescription" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "declared_path" => APIDict("type" => "string", "description" => "Path based on the @system declaration that introduced the variable."),
                "target_path" => APIDict("type" => "string", "description" => "Object-access path accepted by simulate/visualize target, x, and y fields."),
                "alias" => APIDict("type" => ["string", "null"]),
                "description" => APIDict("type" => "string"),
                "state" => APIDict("type" => ["string", "null"]),
                "type" => APIDict("type" => ["string", "null"]),
                "unit" => APIDict("type" => ["string", "null"]),
                "tags" => APIDict("type" => "object"),
                "dependencies" => APIDict("type" => "array", "items" => APIDict("type" => "string")),
                "role" => APIDict("enum" => ["parameter", "output", "table", "internal"]),
            ),
            "required" => [
                "system", "name", "declared_path", "target_path", "alias",
                "description", "state", "type", "unit", "tags",
                "dependencies", "role",
            ],
        ),
        "ParameterDescription" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "config_path" => APIDict("type" => "string", "description" => "Preferred system-keyed configuration path."),
                "declared_path" => APIDict("type" => "string", "description" => "Path based on the @system declaration that introduced the parameter."),
                "accepted_config_paths" => APIDict("type" => "array", "items" => APIDict("type" => "string")),
                "target_path" => APIDict("type" => "string", "description" => "Object-access path accepted by simulate/visualize target, x, and y fields."),
                "alias" => APIDict("type" => ["string", "null"]),
                "description" => APIDict("type" => "string"),
                "default" => APIDict("\$ref" => "#/definitions/Value"),
                "unit" => APIDict("type" => ["string", "null"]),
                "state" => APIDict("type" => ["string", "null"]),
                "tags" => APIDict("type" => "object"),
                "dependencies" => APIDict("type" => "array", "items" => APIDict("type" => "string")),
                "role" => APIDict("enum" => ["parameter", "table"]),
            ),
            "required" => [
                "system", "name", "config_path", "declared_path",
                "accepted_config_paths", "target_path", "alias", "description",
                "default", "unit", "state", "tags", "dependencies", "role",
            ],
        ),
        "TableDescription" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "config_path" => APIDict("type" => "string"),
                "declared_path" => APIDict("type" => "string"),
                "accepted_config_paths" => APIDict("type" => "array", "items" => APIDict("type" => "string")),
                "target_path" => APIDict("type" => "string"),
                "description" => APIDict("type" => "string"),
                "state" => APIDict("enum" => ["provide"]),
                "index" => APIDict("type" => ["string", "number", "boolean", "null"]),
                "tags" => APIDict("type" => "object"),
                "consumers" => APIDict("type" => "array", "items" => APIDict(
                    "type" => "object",
                    "properties" => APIDict(
                        "variable" => APIDict("type" => "string"),
                        "name" => APIDict("type" => "string"),
                        "column" => APIDict("type" => ["string", "number", "boolean", "null"]),
                        "unit" => APIDict("type" => ["string", "null"]),
                    ),
                )),
                "role" => APIDict("enum" => ["table"]),
            ),
            "required" => [
                "system", "name", "config_path", "declared_path",
                "accepted_config_paths", "target_path", "description", "state",
                "index", "tags", "consumers", "role",
            ],
        ),
        "ModelDescription" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "contract" => APIDict("type" => "object"),
                "model" => APIDict("type" => "object"),
                "systems" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/SystemDescription")),
                "parameters" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/ParameterDescription")),
                "variables" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/VariableDescription")),
                "tables" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/TableDescription")),
            ),
            "required" => ["contract", "model", "systems", "parameters", "variables", "tables"],
        ),
        "WidgetControl" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "kind" => APIDict("enum" => ["number", "checkbox", "file", "text"]),
                "role" => APIDict("enum" => ["parameter", "table"]),
                "source" => APIDict(
                    "enum" => ["dsl", "runtime"],
                    "description" => "Origin of the control metadata.",
                ),
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "path" => APIDict("type" => "string"),
                "config_path" => APIDict("type" => "string"),
                "declared_path" => APIDict("type" => "string"),
                "accepted_config_paths" => APIDict(
                    "type" => "array",
                    "items" => APIDict("type" => "string"),
                ),
                "alias" => APIDict("type" => ["string", "null"]),
                "label" => APIDict("type" => "string"),
                "description" => APIDict("type" => "string"),
                "unit" => APIDict("type" => ["string", "null"]),
                "default" => APIDict("description" => "JSON-compatible default value."),
                "value_type" => APIDict("type" => "string"),
                "state" => APIDict("type" => "string"),
                "min" => APIDict("type" => ["number", "null"]),
                "max" => APIDict("type" => ["number", "null"]),
                "step" => APIDict("type" => ["number", "null"]),
                "accept" => APIDict("type" => ["string", "null"]),
                "columns" => APIDict("type" => "array"),
            ),
            "required" => [
                "kind", "role", "source", "system", "name", "path",
                "config_path", "accepted_config_paths", "label", "description",
                "unit", "default", "value_type", "state", "min", "max",
                "step", "accept", "columns",
            ],
        ),
        "WidgetPayload" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "title" => APIDict("type" => "string"),
                "contract" => APIDict("type" => "object"),
                "model" => APIDict("type" => "object"),
                "systems" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/SystemDescription")),
                "controls" => APIDict(
                    "type" => "array",
                    "items" => APIDict("\$ref" => "#/definitions/WidgetControl"),
                ),
                "outputs" => APIDict("type" => "array", "items" => APIDict(
                    "oneOf" => [
                        APIDict("\$ref" => "#/definitions/VariableDescription"),
                        APIDict("\$ref" => "#/definitions/ParameterDescription"),
                    ],
                )),
                "tables" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/TableDescription")),
                "simulation" => APIDict("type" => "object"),
                "visualize" => APIDict("type" => "object"),
                "panels" => APIDict("type" => "array"),
                "sweeps" => APIDict("type" => "array"),
                "external_inputs" => APIDict("type" => "array"),
                "external_sources" => APIDict("type" => "array"),
            ),
        ),
        "Value" => APIDict(
            "oneOf" => [
                APIDict("type" => "string"),
                APIDict("type" => "number"),
                APIDict("type" => "boolean"),
                APIDict(
                    "type" => "object",
                    "properties" => APIDict(
                        "value" => APIDict("description" => "Plain JSON value without units."),
                        "type" => APIDict("type" => "string"),
                        "unit" => APIDict("type" => ["string", "null"]),
                        "timezone" => APIDict("type" => "string"),
                    ),
                    "required" => ["value"],
                ),
            ],
        ),
        "ConfigEntry" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "path" => APIDict("type" => "string", "description" => "Preferred form using config_path or accepted_config_paths from ModelDescription."),
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "value" => APIDict(
                    "oneOf" => [
                        APIDict("\$ref" => "#/definitions/Value"),
                        APIDict("\$ref" => "#/definitions/TableInput"),
                    ],
                ),
            ),
            "required" => ["value"],
        ),
        "NameMapping" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "name" => APIDict("type" => "string", "description" => "Output column name produced by Cropbox."),
                "path" => APIDict("type" => "string", "description" => "Variable path accepted by Cropbox, such as s.L[1].θ."),
                "target" => APIDict("type" => "string", "description" => "Alias for path."),
                "value" => APIDict("type" => "string", "description" => "Alias for path."),
            ),
            "required" => ["name"],
        ),
        "NameSelection" => APIDict(
            "oneOf" => [
                APIDict("type" => "string"),
                APIDict("type" => "array", "items" => APIDict(
                    "oneOf" => [
                        APIDict("type" => "string"),
                        APIDict("\$ref" => "#/definitions/NameMapping"),
                    ],
                )),
                APIDict("type" => "object", "description" => "Path map keyed by output column name."),
            ],
        ),
        "StepSelection" => APIDict(
            "type" => "object",
            "description" => "Parameter sweep used by visualize requests. The target can be supplied as `path` or as `system` and `name`; values can be supplied explicitly or by start/stop/step bounds.",
            "properties" => APIDict(
                "path" => APIDict("type" => "string", "description" => "Parameter path such as Weather.CO2."),
                "system" => APIDict("type" => "string"),
                "name" => APIDict("type" => "string"),
                "values" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/Value")),
                "start" => APIDict("\$ref" => "#/definitions/Value"),
                "stop" => APIDict("\$ref" => "#/definitions/Value"),
                "step" => APIDict("\$ref" => "#/definitions/Value"),
                "min" => APIDict("\$ref" => "#/definitions/Value"),
                "max" => APIDict("\$ref" => "#/definitions/Value"),
                "unit" => APIDict("type" => ["string", "null"]),
            ),
        ),
        "Column" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "name" => APIDict("type" => "string"),
                "type" => APIDict("type" => "string"),
                "unit" => APIDict("type" => ["string", "null"]),
                "timezone" => APIDict("type" => "string"),
            ),
            "required" => ["name"],
        ),
        "TableInput" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "type" => APIDict("enum" => ["DataFrame", "CSV"]),
                "filename" => APIDict("type" => "string"),
                "content" => APIDict("type" => "string"),
                "columns" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/Column")),
                "rows" => APIDict("type" => "array", "items" => APIDict("type" => "array")),
            ),
            "required" => ["type"],
        ),
        "SimulationRequest" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "config" => APIDict("type" => "object"),
                "config_entries" => APIDict(
                    "oneOf" => [
                        APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/ConfigEntry")),
                        APIDict("type" => "object", "description" => "Path-value object keyed by config_path."),
                    ],
                ),
                "configs" => APIDict("type" => "array"),
                "index" => APIDict("\$ref" => "#/definitions/NameSelection"),
                "target" => APIDict("\$ref" => "#/definitions/NameSelection"),
                "stop" => APIDict("\$ref" => "#/definitions/Value"),
                "snap" => APIDict("\$ref" => "#/definitions/Value"),
                "base" => APIDict("type" => "string"),
                "meta" => APIDict("oneOf" => [APIDict("type" => "string"), APIDict("type" => "array", "items" => APIDict("type" => "string"))]),
                "options" => APIDict("type" => "object", "description" => "Native Cropbox constructor/simulation options passed to instance or simulate."),
                "seed" => APIDict("\$ref" => "#/definitions/Value"),
                "nounit" => APIDict("type" => "boolean"),
                "long" => APIDict("type" => "boolean"),
                "api_options" => APIDict("type" => "object", "description" => "Transport-only options such as verbose execution or response formatting."),
            ),
        ),
        "SimulationResponse" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "status" => APIDict("enum" => ["ok"]),
                "contract_version" => APIDict("type" => "string"),
                "model" => APIDict("type" => "string"),
                "columns" => APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/Column")),
                "rows" => APIDict("type" => "array", "items" => APIDict("type" => "array")),
                "summary" => APIDict("type" => "object"),
            ),
            "required" => ["status", "contract_version", "columns", "rows"],
        ),
        "VisualizationRequest" => APIDict(
            "allOf" => [
                APIDict("\$ref" => "#/definitions/SimulationRequest"),
                APIDict("type" => "object", "properties" => APIDict(
                    "x" => APIDict("type" => "string"),
                    "y" => APIDict("oneOf" => [APIDict("type" => "string"), APIDict("type" => "array", "items" => APIDict("type" => "string"))]),
                    "kind" => APIDict("type" => "string"),
                    "backend" => APIDict("type" => "string"),
                    "xstep" => APIDict("\$ref" => "#/definitions/StepSelection"),
                    "plot" => APIDict(
                        "type" => "object",
                        "properties" => APIDict(
                            "xlim" => APIDict("type" => "array", "minItems" => 2, "maxItems" => 2, "items" => APIDict("type" => "number")),
                            "ylim" => APIDict("type" => "array", "minItems" => 2, "maxItems" => 2, "items" => APIDict("type" => "number")),
                            "linestyles" => APIDict(
                                "type" => "array",
                                "items" => APIDict("enum" => ["solid", "dash", "dot", "dashdot"]),
                            ),
                        ),
                    ),
                )),
            ],
        ),
        "VisualizationResponse" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "status" => APIDict("enum" => ["ok"]),
                "contract_version" => APIDict("type" => "string"),
                "model" => APIDict("type" => "string"),
                "format" => APIDict("enum" => ["svg"]),
                "content_type" => APIDict("enum" => ["image/svg+xml"]),
                "body" => APIDict("type" => "string"),
                "summary" => APIDict("type" => "object"),
            ),
            "required" => ["status", "contract_version", "format", "content_type", "body"],
        ),
        "EvaluationRequest" => APIDict(
            "allOf" => [
                APIDict("\$ref" => "#/definitions/SimulationRequest"),
                APIDict("type" => "object", "properties" => APIDict(
                    "observed" => APIDict("\$ref" => "#/definitions/TableInput"),
                    "obs" => APIDict("\$ref" => "#/definitions/TableInput"),
                    "metric" => APIDict("enum" => ["rmse", "nrmse", "rmspe", "mae", "mape", "ef", "dr"]),
                )),
            ],
        ),
        "EvaluationResponse" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "status" => APIDict("enum" => ["ok"]),
                "contract_version" => APIDict("type" => "string"),
                "model" => APIDict("type" => "string"),
                "operation" => APIDict("enum" => ["evaluate"]),
                "metric" => APIDict("type" => "string"),
                "target" => APIDict("\$ref" => "#/definitions/NameSelection"),
                "value" => APIDict("\$ref" => "#/definitions/Value"),
                "summary" => APIDict("type" => "object"),
            ),
            "required" => ["status", "contract_version", "operation", "metric", "target", "value"],
        ),
        "ParameterRange" => APIDict(
            "oneOf" => [
                APIDict(
                    "type" => "object",
                    "properties" => APIDict(
                        "system" => APIDict("type" => "string"),
                        "name" => APIDict("type" => "string"),
                        "path" => APIDict("type" => "string"),
                        "lower" => APIDict("\$ref" => "#/definitions/Value"),
                        "upper" => APIDict("\$ref" => "#/definitions/Value"),
                        "min" => APIDict("\$ref" => "#/definitions/Value"),
                        "max" => APIDict("\$ref" => "#/definitions/Value"),
                        "unit" => APIDict("type" => ["string", "null"]),
                    ),
                ),
                APIDict("type" => "array", "minItems" => 2, "maxItems" => 2),
            ],
        ),
        "CalibrationRequest" => APIDict(
            "allOf" => [
                APIDict("\$ref" => "#/definitions/EvaluationRequest"),
                APIDict("type" => "object", "properties" => APIDict(
                    "parameters" => APIDict(
                        "oneOf" => [
                            APIDict("type" => "array", "items" => APIDict("\$ref" => "#/definitions/ParameterRange")),
                            APIDict("type" => "object"),
                        ],
                    ),
                    "optim" => APIDict("type" => "object"),
                )),
            ],
        ),
        "CalibrationResponse" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "status" => APIDict("enum" => ["ok"]),
                "contract_version" => APIDict("type" => "string"),
                "model" => APIDict("type" => "string"),
                "operation" => APIDict("enum" => ["calibrate"]),
                "metric" => APIDict("type" => "string"),
                "config" => APIDict("type" => "object"),
                "summary" => APIDict("type" => "object"),
            ),
            "required" => ["status", "contract_version", "operation", "metric", "config"],
        ),
        "ErrorResponse" => APIDict(
            "type" => "object",
            "properties" => APIDict(
                "status" => APIDict("enum" => ["error"]),
                "error" => APIDict("type" => "object", "properties" => APIDict(
                    "code" => APIDict("type" => "string"),
                    "category" => APIDict("enum" => ["syntax", "validation", "execution", "routing"]),
                    "message" => APIDict("type" => "string"),
                    "path" => APIDict("type" => "string"),
                    "retryable" => APIDict("type" => "boolean"),
                )),
                "contract_version" => APIDict("type" => "string"),
            ),
            "required" => ["status", "error"],
        ),
    ),
)

api_openapi_ref(value::AbstractDict) = APIDict(
    string(k) => string(k) == "\$ref" && v isa AbstractString ?
        replace(v, "#/definitions/" => "#/components/schemas/") :
        api_openapi_ref(v)
    for (k, v) in value
)
api_openapi_ref(value::AbstractVector) = api_openapi_ref.(value)
api_openapi_ref(value) = value

api_openapi_schema(name::AbstractString) = APIDict("\$ref" => "#/components/schemas/$name")
api_openapi_object_schema() = APIDict("type" => "object")
api_openapi_string_schema() = APIDict("type" => "string")

api_openapi_content(schema; content_type="application/json", examples=nothing) = begin
    media = APIDict("schema" => schema)
    isnothing(examples) || (media["examples"] = examples)
    APIDict(content_type => media)
end

api_openapi_response(schema; description="Successful response", content_type="application/json", examples=nothing) = APIDict(
    "description" => description,
    "content" => api_openapi_content(schema; content_type, examples),
)

api_openapi_error_response() = api_openapi_response(
    api_openapi_schema("ErrorResponse");
    description="Machine-readable error response",
)

api_openapi_get(summary, response_schema; response_examples=nothing, content_type="application/json", deprecated=false, description=nothing) = begin
    operation = APIDict(
    "summary" => summary,
    "deprecated" => deprecated,
    "responses" => APIDict(
        "200" => api_openapi_response(response_schema; content_type, examples=response_examples),
        "400" => api_openapi_error_response(),
        "404" => api_openapi_error_response(),
        "500" => api_openapi_error_response(),
    ),
)
    isnothing(description) || (operation["description"] = description)
    operation
end

api_openapi_post(summary, request_schema, response_schema; request_examples=nothing, response_examples=nothing) = APIDict(
    "summary" => summary,
    "requestBody" => APIDict(
        "required" => true,
        "content" => api_openapi_content(request_schema; examples=request_examples),
    ),
    "responses" => APIDict(
        "200" => api_openapi_response(response_schema; examples=response_examples),
        "400" => api_openapi_error_response(),
        "422" => api_openapi_error_response(),
        "404" => api_openapi_error_response(),
        "500" => api_openapi_error_response(),
    ),
)

api_openapi_example_value(value, unit) = begin
    if isnothing(unit) || unit == ""
        value
    else
        APIDict("value" => value, "unit" => unit)
    end
end

api_openapi_first(items, predicate) = begin
    for item in items
        predicate(item) && return item
    end
    isempty(items) ? nothing : first(items)
end

api_openapi_metadata_excerpt(item) = begin
    isnothing(item) && return APIDict()
    excerpt = APIDict()
    for key in ("system", "name", "config_path", "target_path", "alias", "description", "unit", "state", "role")
        haskey(item, key) || continue
        value = item[key]
        isnothing(value) && continue
        value == "" && continue
        excerpt[key] = value
    end
    excerpt
end

api_openapi_examples() = begin
    p = APIDict(
        "system" => "Phenology",
        "name" => "phyllochron",
        "config_path" => "Phenology.phyllochron",
        "target_path" => "phyllochron",
        "alias" => "leaf_appearance_interval",
        "description" => "Thermal time required for the appearance of one leaf.",
        "unit" => "K*d",
        "state" => "preserve",
        "role" => "parameter",
        "default" => APIDict("value" => 50, "type" => "Int64", "unit" => "K*d"),
    )
    v = APIDict(
        "system" => "Phenology",
        "name" => "leaves_appeared",
        "target_path" => "leaves_appeared",
        "alias" => "L",
        "description" => "Cumulative number of appeared leaves.",
        "unit" => nothing,
        "state" => "track",
        "role" => "output",
    )
    model_name = "Phenology"
    api_openapi_examples(model_name, p, v)
end

api_openapi_examples(S::Type{<:System}; config=()) = api_openapi_examples(describe(S; config))

api_openapi_examples(description::AbstractDict) = begin
    parameters = get(description, "parameters", [])
    variables = get(description, "variables", [])
    p = api_openapi_first(parameters, item ->
        get(item, "unit", nothing) !== nothing ||
        !isempty(get(item, "description", "")) ||
        get(item, "alias", nothing) !== nothing
    )
    v = api_openapi_first(variables, item ->
        get(item, "role", nothing) == "output" &&
        (!isempty(get(item, "description", "")) || get(item, "unit", nothing) !== nothing || get(item, "alias", nothing) !== nothing)
    )
    isnothing(v) && (v = api_openapi_first(variables, item -> get(item, "role", nothing) == "output"))
    model_name = get(get(description, "model", APIDict()), "name", "CropboxModel")
    api_openapi_examples(model_name, p, v)
end

api_openapi_examples(model_name, parameter, variable) = begin
    isnothing(parameter) && (parameter = APIDict(
        "system" => model_name,
        "name" => "parameter",
        "config_path" => "$model_name.parameter",
        "description" => "Example configurable parameter.",
        "unit" => nothing,
        "state" => "preserve",
        "role" => "parameter",
        "default" => APIDict("value" => 1),
    ))
    isnothing(variable) && (variable = APIDict(
        "system" => model_name,
        "name" => "output",
        "target_path" => "output",
        "description" => "Example model output.",
        "unit" => nothing,
        "state" => "track",
        "role" => "output",
    ))
    ppath = get(parameter, "config_path", "$model_name.parameter")
    pname = get(parameter, "name", "parameter")
    psystem = get(parameter, "system", model_name)
    punit = get(parameter, "unit", nothing)
    default_object = get(parameter, "default", APIDict("value" => 1))
    pdefault = default_object isa AbstractDict ? get(default_object, "value", 1) : default_object
    pnumber = pdefault isa Number ? pdefault : 1
    target = get(variable, "target_path", get(variable, "name", "output"))
    vunit = get(variable, "unit", nothing)
    APIDict(
        "model" => APIDict(
            "model_excerpt" => APIDict(
                "summary" => "Model metadata projected from Cropbox DSL",
                "value" => APIDict(
                    "model" => APIDict("name" => model_name),
                    "parameters" => [api_openapi_metadata_excerpt(parameter)],
                    "variables" => [api_openapi_metadata_excerpt(variable)],
                ),
            ),
        ),
        "widgets" => APIDict(
            "widget_excerpt" => APIDict(
                "summary" => "Dashboard controls generated from the same metadata",
                "value" => APIDict(
                    "model" => APIDict("name" => model_name),
                    "controls" => [
                        APIDict(
                            "kind" => "number",
                            "role" => "parameter",
                            "path" => ppath,
                            "label" => ppath,
                            "description" => get(parameter, "description", ""),
                            "unit" => punit,
                            "default" => pdefault,
                        ),
                    ],
                    "outputs" => [api_openapi_metadata_excerpt(variable)],
                ),
            ),
        ),
        "simulation_request" => APIDict(
            "unit_config_entry" => APIDict(
                "summary" => "Override a DSL parameter with value and unit",
                "value" => APIDict(
                    "config_entries" => [
                        APIDict("path" => ppath, "value" => api_openapi_example_value(pdefault, punit)),
                    ],
                    "stop" => APIDict("value" => 5, "unit" => "d"),
                    "target" => [target],
                ),
            ),
        ),
        "simulation_response" => APIDict(
            "unit_table" => APIDict(
                "summary" => "Simulation table with per-column units",
                "value" => APIDict(
                    "status" => "ok",
                    "model" => model_name,
                    "columns" => [
                        APIDict("name" => "time", "type" => "Float64", "unit" => "d"),
                        APIDict("name" => target, "type" => "Float64", "unit" => vunit),
                    ],
                    "rows" => [[0, 0], [5, 1]],
                    "summary" => APIDict("nrow" => 2, "ncol" => 2),
                ),
            ),
        ),
        "visualization_request" => APIDict(
            "line_svg" => APIDict(
                "summary" => "Request an SVG plot for one or more output variables",
                "value" => APIDict(
                    "config_entries" => [
                        APIDict("path" => ppath, "value" => api_openapi_example_value(pdefault, punit)),
                    ],
                    "stop" => APIDict("value" => 5, "unit" => "d"),
                    "x" => "time",
                    "y" => target,
                    "kind" => "line",
                    "backend" => "Gadfly",
                ),
            ),
        ),
        "visualization_response" => APIDict(
            "svg_payload" => APIDict(
                "summary" => "Visualization response carries SVG as a JSON string",
                "value" => APIDict(
                    "status" => "ok",
                    "model" => model_name,
                    "format" => "svg",
                    "content_type" => "image/svg+xml",
                    "body" => "<svg><!-- cropped for documentation --></svg>",
                ),
            ),
        ),
        "evaluation_request" => APIDict(
            "observed_table" => APIDict(
                "summary" => "Observed CSV/DataFrame rows use the same table contract as provide inputs",
                "value" => APIDict(
                    "observed" => APIDict(
                        "type" => "DataFrame",
                        "columns" => [
                            APIDict("name" => "time", "type" => "Float64", "unit" => "d"),
                            APIDict("name" => target, "type" => "Float64", "unit" => vunit),
                        ],
                        "rows" => [[0, 0], [5, 1]],
                    ),
                    "target" => [target],
                    "metric" => "rmse",
                    "stop" => APIDict("value" => 5, "unit" => "d"),
                ),
            ),
        ),
        "evaluation_response" => APIDict(
            "metric" => APIDict(
                "summary" => "Metric result returned as a scalar payload",
                "value" => APIDict(
                    "status" => "ok",
                    "model" => model_name,
                    "operation" => "evaluate",
                    "metric" => "rmse",
                    "value" => 0,
                    "summary" => APIDict("target" => target),
                ),
            ),
        ),
        "calibration_request" => APIDict(
            "bounded_parameter" => APIDict(
                "summary" => "Calibration can reuse config paths as bounded parameter names",
                "value" => APIDict(
                    "observed" => APIDict(
                        "type" => "DataFrame",
                        "columns" => [
                            APIDict("name" => "time", "type" => "Float64", "unit" => "d"),
                            APIDict("name" => target, "type" => "Float64", "unit" => vunit),
                        ],
                        "rows" => [[0, 0], [5, 1]],
                    ),
                    "target" => [target],
                    "metric" => "rmse",
                    "parameters" => [
                        APIDict("path" => ppath, "lower" => api_openapi_example_value(0, punit), "upper" => api_openapi_example_value(2 * pnumber, punit)),
                    ],
                    "stop" => APIDict("value" => 5, "unit" => "d"),
                ),
            ),
        ),
        "calibration_response" => APIDict(
            "fitted_config" => APIDict(
                "summary" => "Fitted values are returned as configuration entries",
                "value" => APIDict(
                    "status" => "ok",
                    "model" => model_name,
                    "operation" => "calibrate",
                    "metric" => "rmse",
                    "config" => APIDict(string(psystem) => APIDict(string(pname) => api_openapi_example_value(pdefault, punit))),
                    "summary" => APIDict("target" => target),
                ),
            ),
        ),
    )
end

api_openapi() = api_openapi(api_openapi_examples())
api_openapi(S::Type{<:System}; config=()) = api_openapi(api_openapi_examples(S; config))

api_openapi(examples::AbstractDict) = begin
    schema = api_schema()
    components = api_openapi_ref(schema["definitions"])
    APIDict(
        "openapi" => "3.1.0",
        "info" => APIDict(
            "title" => "Cropbox Web API",
            "version" => API_CONTRACT_VERSION,
            "description" => "OpenAPI view of the Cropbox model-service routes used for model metadata, simulation, visualization, evaluation, calibration, dashboard metadata, and schema discovery.",
        ),
        "x-cropbox-contract" => api_contract_metadata(),
        "paths" => APIDict(
            "/api/model" => APIDict(
                "get" => api_openapi_get("Describe a Cropbox model", api_openapi_schema("ModelDescription"); response_examples=examples["model"]),
            ),
            "/api/dashboard" => APIDict(
                "get" => api_openapi_get("Return generated dashboard metadata", api_openapi_schema("WidgetPayload"); response_examples=examples["widgets"]),
            ),
            "/api/schema" => APIDict(
                "get" => api_openapi_get("Return JSON Schema-style fragments", api_openapi_object_schema()),
            ),
            "/api/openapi" => APIDict(
                "get" => api_openapi_get("Return this OpenAPI document", api_openapi_object_schema()),
            ),
            "/api/docs" => APIDict(
                "get" => api_openapi_get("Render Swagger UI for this service", api_openapi_string_schema(); content_type="text/html"),
            ),
            "/api/simulate" => APIDict(
                "post" => api_openapi_post(
                    "Run a Cropbox simulation",
                    api_openapi_schema("SimulationRequest"),
                    api_openapi_schema("SimulationResponse");
                    request_examples=examples["simulation_request"],
                    response_examples=examples["simulation_response"],
                ),
            ),
            "/api/visualize" => APIDict(
                "post" => api_openapi_post(
                    "Run a Cropbox visualization",
                    api_openapi_schema("VisualizationRequest"),
                    api_openapi_schema("VisualizationResponse");
                    request_examples=examples["visualization_request"],
                    response_examples=examples["visualization_response"],
                ),
            ),
            "/api/evaluate" => APIDict(
                "post" => api_openapi_post(
                    "Evaluate model output against observed rows",
                    api_openapi_schema("EvaluationRequest"),
                    api_openapi_schema("EvaluationResponse");
                    request_examples=examples["evaluation_request"],
                    response_examples=examples["evaluation_response"],
                ),
            ),
            "/api/calibrate" => APIDict(
                "post" => api_openapi_post(
                    "Fit bounded parameter configurations against observed rows",
                    api_openapi_schema("CalibrationRequest"),
                    api_openapi_schema("CalibrationResponse");
                    request_examples=examples["calibration_request"],
                    response_examples=examples["calibration_response"],
                ),
            ),
        ),
        "components" => APIDict(
            "schemas" => components,
        ),
    )
end

swagger_ui_html() = raw"""
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cropbox Web API Docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
  <style>
    body { margin: 0; background: #f7f9fb; }
    .topbar { display: none; }
    .fallback { padding: 10px 16px; font: 13px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #516070; background: #fff; border-bottom: 1px solid #dde4ec; }
    .fallback a { color: #176b68; }
  </style>
</head>
<body>
  <div class="fallback">
    Cropbox serves a machine-readable OpenAPI document at
    <a href="/api/openapi"><code>/api/openapi</code></a>. This page renders it with Swagger UI.
  </div>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.addEventListener("load", () => {
      window.ui = SwaggerUIBundle({
        url: "/api/openapi",
        dom_id: "#swagger-ui",
        deepLinking: true,
        presets: [SwaggerUIBundle.presets.apis],
        layout: "BaseLayout"
      });
    });
  </script>
</body>
</html>
"""

dashboard_html() = read(joinpath(@__DIR__, "dashboard.html"), String)

export describe, serve, dashboard
