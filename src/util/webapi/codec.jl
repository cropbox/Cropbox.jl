# JSON codec for Cropbox values: units, typed scalars, tables and configurations.
#
# `decode` turns JSON-compatible request values into Julia values and `encode`
# turns Julia results back into JSON-compatible values. Both are generic over
# Cropbox types (Quantity, Config, DataFrame) so other JSON consumers can reuse
# them.

using CSV: CSV
using DataFrames: DataFrame, DataFrames, nrow
using DataStructures: OrderedDict
using Dates: Date, DateTime
using JSON: JSON
using TimeZones: TimeZone, ZonedDateTime, astimezone
using Unitful: Unitful, Quantity

const APIDict = Dict{String,Any}
const API_CONTRACT_VERSION = "0.2.0"

"Request error with an HTTP category: `syntax` (400), `validation` (422), `routing` (404/405) or `execution` (500)."
struct APIRequestError <: Exception
    category::String
    message::String
end
Base.showerror(io::IO, e::APIRequestError) = print(io, e.message)
apierror(message, category="validation") = throw(APIRequestError(category, String(message)))

"Recursively convert dictionary keys to strings (JSON objects may arrive with Symbol keys from Julia code)."
stringkeys(d::AbstractDict) = APIDict(string(k) => stringkeys(v) for (k, v) in d)
stringkeys(d::NamedTuple) = stringkeys(Dict(pairs(d)))
stringkeys(v::AbstractVector) = Any[stringkeys(x) for x in v]
stringkeys(v) = v

"An optional JSON object with string keys: `nothing` and `()` are empty; anything else must be an object."
asobject(::Nothing) = APIDict()
asobject(::Tuple{}) = APIDict()
asobject(x::Union{AbstractDict,NamedTuple}) = stringkeys(x)
asobject(x) = apierror("Expected an object, got `$(typeof(x))`")

# --- units and scalar types ---------------------------------------------------

const UNIT_CHARS = Set(('°', '%', 'µ', 'μ', '*', '/', '^', '.', '-', '+', '(', ')', '⁻', '⁺', '⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'))
const SUPERSCRIPTS = Dict('⁻' => '-', '⁺' => '+', '⁰' => '0', '¹' => '1', '²' => '2', '³' => '3', '⁴' => '4', '⁵' => '5', '⁶' => '6', '⁷' => '7', '⁸' => '8', '⁹' => '9')

"""
    parseunit(s) -> Unitful.Units

Parse a unit label such as `"m"`, `"K*d"`, `"μmol/(m^2*s)"` or `"m s⁻¹"` with
`Unitful.uparse`, which only resolves unit names and arithmetic (no code is
evaluated). Returns `nothing` for `nothing` or a blank string.
"""
parseunit(::Nothing) = nothing
parseunit(u::Unitful.Units) = u
parseunit(s::AbstractString) = begin
    t = strip(s)
    isempty(t) && return nothing
    all(c -> isletter(c) || isdigit(c) || isspace(c) || c in UNIT_CHARS, t) || apierror("Invalid characters in unit `$s`")
    u = try
        Unitful.uparse(t)
    catch
        try
            Unitful.uparse(expandunit(t))
        catch
            apierror("Unsupported unit `$s`")
        end
    end
    u isa Unitful.Units || apierror("`$s` does not resolve to a unit")
    u
end

# `m s⁻¹` -> `m*s^-1`, `K d` -> `K*d`
expandunit(s::AbstractString) = begin
    e = replace(s, r"[⁻⁺⁰¹²³⁴⁵⁶⁷⁸⁹]+" => m -> "^" * join(SUPERSCRIPTS[c] for c in m))
    replace(strip(e), r"\s+" => "*")
end

"Unit label that `parseunit` accepts back: `K*d`, `m*s^-1`, `°C`; `nothing` when unitless."
unitlabel(u) = hasunit(u) ? replace(string(u), " " => "*", "%" => "percent") : nothing

const API_TYPES = Dict{String,Type}(
    "Bool" => Bool, "Int" => Int, "Int64" => Int, "Float64" => Float64, "Float32" => Float64,
    "String" => String, "Symbol" => Symbol, "Date" => Date, "DateTime" => DateTime, "ZonedDateTime" => ZonedDateTime,
)
const TEMPORAL_TYPES = ("Date", "DateTime", "ZonedDateTime")

"Scalar type converted on input for a type name; other names (`Vector{Float64}`, `Any`) leave values as parsed."
apitype(::Nothing) = nothing
apitype(s::AbstractString) = get(API_TYPES, s, nothing)
apitype(s) = apierror("`type` must be a string, got `$s`")

"Type name under which encoded values of type `T` read back: rationals travel as floats; `missing` and `nothing` have none."
wiretype(T::Type) = begin
    N = nonmissingtype(T)
    N in (Union{}, Nothing) ? nothing : string(N <: Rational ? Float64 : N)
end

# --- decode: JSON -> Julia -----------------------------------------------------

"""
    decode(x)

Convert a JSON-compatible value into a Julia value:

- `null`, numbers, booleans and strings pass through;
- `{"value": v, "unit": "m", "type": "Float64"}` becomes a (typed) quantity; `v` may be an array;
- `{"type": "CSV", "content": ...}` and `{"type": "DataFrame", "columns": ..., "rows": ...}` become a `DataFrame` (see `decodetable`);
- arrays are decoded element-wise.
"""
decode(x::AbstractVector) = Any[decode(v) for v in x]
decode(x::AbstractDict) = begin
    d = stringkeys(x)
    kind = get(d, "type", nothing)
    kind in ("CSV", "DataFrame") && return decodetable(d)
    haskey(d, "value") || apierror("Value objects require `value` (or `type` CSV/DataFrame for tables)")
    v = decodetyped(d["value"], kind; timezone=get(d, "timezone", nothing))
    u = parseunit(get(d, "unit", nothing))
    isnothing(u) ? v : unitfy(v, u)
end
decode(x) = x

"Coerce `v` (element-wise for arrays) to the type named by `kind` (see `apitype`) or to a `Type`; `nothing`/`missing` pass through."
decodetyped(v, kind; timezone=nothing) = decodetyped(v, apitype(kind); timezone)
decodetyped(v, ::Nothing; timezone=nothing) = v
decodetyped(v, T::Type; timezone=nothing) = (isnothing(v) || ismissing(v)) ? v : coercevalue(v, T, timezone)
decodetyped(v::AbstractVector, T::Type; timezone=nothing) = [decodetyped(x, T; timezone) for x in v]
coercevalue(v, ::Type{Symbol}, tz) = Symbol(v)
coercevalue(v, ::Type{String}, tz) = string(v)
coercevalue(v, ::Type{Bool}, tz) = parsebool(v)
coercevalue(v, ::Type{Int}, tz) = v isa AbstractString ? parse(Int, v) : Int(v)
coercevalue(v, ::Type{Float64}, tz) = v isa AbstractString ? parse(Float64, v) : Float64(v)
coercevalue(v, ::Type{Date}, tz) = v isa Date ? v : Date(v)
coercevalue(v, ::Type{DateTime}, tz) = v isa DateTime ? v : DateTime(v)
coercevalue(v, ::Type{ZonedDateTime}, tz) = decodezoned(v, tz)
coercevalue(v, T::Type, tz) = apierror("Unsupported type `$T`")

decodezoned(v::ZonedDateTime, timezone) = isnothing(timezone) ? v : astimezone(v, TimeZone(timezone))
decodezoned(v::DateTime, timezone) = isnothing(timezone) ?
    apierror("ZonedDateTime values without an offset require `timezone` metadata") :
    ZonedDateTime(v, TimeZone(timezone))
decodezoned(v, timezone) = begin
    s = String(v)
    parsed = try ZonedDateTime(s) catch; nothing end
    isnothing(parsed) || return decodezoned(parsed, timezone)
    isnothing(timezone) && apierror("ZonedDateTime value `$s` requires an offset or `timezone` metadata")
    ZonedDateTime(DateTime(s), TimeZone(timezone))
end

parsebool(::Nothing) = nothing
parsebool(v::Bool) = v
parsebool(v::Number) = !iszero(v)
parsebool(v::AbstractString) = begin
    s = lowercase(strip(v))
    s in ("true", "1", "yes", "on") && return true
    s in ("false", "0", "no", "off") && return false
    apierror("Invalid boolean value `$v`")
end
parsebool(v) = Bool(v)

"""
    decodetable(d) -> DataFrame

Build a `DataFrame` from a table payload. `{"type": "CSV", "content": "..."}`
parses CSV text; `{"type": "DataFrame", "columns": [...], "rows": [[...], ...]}`
takes row arrays. Optional `columns` metadata (`name`, `type`, `unit`,
`timezone`) converts and unitfies columns. CSV headers may alternatively carry
`name (unit)` or `name (:Type)` annotations when no `columns` are given.
"""
decodetable(d::AbstractDict) = begin
    columns = [asobject(c) for c in something(get(d, "columns", nothing), [])]
    for c in columns
        haskey(c, "name") || apierror("Every table column requires a `name`")
    end
    df = if d["type"] == "CSV"
        haskey(d, "content") || apierror("CSV payload requires `content`")
        decodecsv(String(d["content"]), columns)
    else
        isempty(columns) && apierror("DataFrame payload requires `columns`")
        rows = something(get(d, "rows", nothing), [])
        rows isa AbstractVector && all(r -> r isa AbstractVector, rows) || apierror("DataFrame payload `rows` must be an array of row arrays")
        for c in columns
            occursin(r"\([^()]+\)\s*$", String(c["name"])) && apierror("Structured table column names must not contain parenthesized metadata; use the column fields instead")
        end
        df = DataFrame()
        for (i, c) in enumerate(columns)
            # absent and `null` cells are `missing`, which plotting and evaluation skip
            df[!, Symbol(c["name"])] = [length(r) >= i && !isnothing(r[i]) ? r[i] : missing for r in rows]
        end
        applycolumns!(df, columns)
    end
    df
end

decodecsv(content::AbstractString, columns) = begin
    header = String.(propertynames(CSV.File(IOBuffer(content); limit=0)))
    implicit = headermetadata.(header)
    if any(!isnothing, implicit)
        isempty(columns) || apierror("CSV header metadata and the `columns` field cannot be used together")
        columns = [isnothing(m) ? APIDict("name" => h) : m for (h, m) in zip(header, implicit)]
        renames = Dict(h => String(m["name"]) for (h, m) in zip(header, implicit) if !isnothing(m))
    else
        renames = Dict{String,String}()
    end
    meta = Dict(String(c["name"]) => c for c in columns)
    # read temporal columns as strings so that offsets and time zones are handled here
    temporal(h) = begin
        c = get(meta, get(renames, h, h), nothing)
        !isnothing(c) && (get(c, "type", nothing) in TEMPORAL_TYPES || haskey(c, "timezone"))
    end
    types = Dict{Symbol,Type}(Symbol(h) => String for h in header if temporal(h))
    df = CSV.read(IOBuffer(content), DataFrame; types)
    isempty(renames) || DataFrames.rename!(df, [Symbol(h) => Symbol(n) for (h, n) in renames]...)
    applycolumns!(df, columns)
end

"`name (unit)` or `name (:Type)` CSV header annotation -> column metadata, or `nothing`."
headermetadata(h::AbstractString) = begin
    m = match(r"^(.+?)\s*\(([^()]+)\)\s*$", h)
    isnothing(m) && return nothing
    name, annotation = strip(m.captures[1]), strip(m.captures[2])
    isempty(name) && apierror("CSV column name cannot be empty")
    if startswith(annotation, ":")
        kind = strip(annotation[2:end])
        haskey(API_TYPES, kind) || apierror("Unsupported CSV column type `$kind`; use the `columns` field with a supported type")
        APIDict("name" => name, "type" => kind)
    else
        parseunit(annotation)
        APIDict("name" => name, "unit" => annotation)
    end
end

"Apply column metadata (`type`, `timezone`, `unit`) in place."
applycolumns!(df::DataFrame, columns) = begin
    for c in columns
        name = Symbol(c["name"])
        name in propertynames(df) || apierror("Table metadata refers to missing column `$(c["name"])`")
        kind = get(c, "type", nothing)
        timezone = get(c, "timezone", nothing)
        T = isnothing(kind) ? (isnothing(timezone) ? nothing : ZonedDateTime) : apitype(kind)
        isnothing(T) || (df[!, name] = decodetyped(df[!, name], T; timezone))
        unit = parseunit(get(c, "unit", nothing))
        if !isnothing(unit)
            T in (Date, DateTime, ZonedDateTime) && apierror("Column `$(c["name"])` is temporal and cannot carry a unit")
            df[!, name] = unitfy(df[!, name], unit)
        end
    end
    df
end

"""
    decodeconfig(x; value=decode) -> Config

Convert a JSON configuration into a `Config`. Two shapes are accepted and may be
mixed: nested `{"System": {"name": value}}` and flat `{"System.name": value}`.
Values are decoded with `value` (scalars, `{value, unit}` objects or tables).
A key without a dot whose object looks like a value or a table is rejected as
a missing system name rather than read as a system.
"""
decodeconfig(::Nothing; value=decode) = configure()
decodeconfig(c::Config; value=decode) = c
decodeconfig(x::AbstractDict; value=decode) = begin
    d = stringkeys(x)
    P = Pair[]
    for (k, v) in d
        dots = count(==('.'), k)
        if dots == 0 && v isa AbstractDict && !haskey(v, "value") && !(get(v, "type", nothing) in ("CSV", "DataFrame"))
            push!(P, Symbol(k) => OrderedDict{Symbol,Any}(Symbol(n) => value(w) for (n, w) in v))
        elseif dots == 1
            push!(P, String(k) => value(v))
        else
            apierror("Configuration key `$k` must be a `System.name` path or a system name holding an object of parameters")
        end
    end
    isempty(P) ? configure() : configure(P...)
end
decodeconfig(x; value=decode) = apierror("Configuration must be an object")

"Convert a flat or nested configuration into `path => value` pairs with `System.name` paths."
flatconfig(c::Config) = ["$(s).$(k)" => v for (s, F) in c for (k, v) in F]

"""Parameter bounds for calibration: `[lo, hi]` or `{"lower": lo, "upper": hi, "unit": "m"}`."""
decodebounds(x::AbstractVector) = begin
    length(x) == 2 || apierror("Parameter range must contain two bounds")
    (decode(x[1]), decode(x[2]))
end
decodebounds(x::AbstractDict) = begin
    d = stringkeys(x)
    lower = decode(get(d, "lower", get(d, "min", nothing)))
    upper = decode(get(d, "upper", get(d, "max", nothing)))
    (isnothing(lower) || isnothing(upper)) && apierror("Parameter range requires lower/upper bounds")
    u = parseunit(get(d, "unit", nothing))
    isnothing(u) ? (lower, upper) : (unitfy(lower, u), unitfy(upper, u))
end
decodebounds(x) = apierror("Unsupported parameter range `$x`")

"Keyword options object -> NamedTuple (`Method`/`TraceMode` strings become Symbols for optimizers)."
decodeoptions(::Nothing) = (;)
decodeoptions(::Tuple{}) = (;)
decodeoptions(o::NamedTuple) = o
decodeoptions(x::AbstractDict) = begin
    d = stringkeys(x)
    (; (Symbol(k) => (k in ("Method", "TraceMode") && v isa AbstractString ? Symbol(v) : decode(v)) for (k, v) in d)...)
end
decodeoptions(x) = apierror("Options must be an object")

# --- encode: Julia -> JSON -----------------------------------------------------

"""
    encode(x)

Convert a Julia value into a JSON-compatible value. Quantities lose their unit
(use `encodevalue` to keep it), non-finite floats become `null`, dates
become ISO strings, `Config` becomes nested objects of value objects and
`DataFrame` becomes a table payload.
"""
encode(::Nothing) = nothing
encode(::Missing) = nothing
encode(x::Bool) = x
encode(x::Integer) = x
encode(x::Rational) = float(x)
encode(x::AbstractFloat) = isfinite(x) ? x : nothing
encode(x::AbstractString) = String(x)
encode(x::Symbol) = string(x)
encode(x::Union{Date,DateTime,ZonedDateTime}) = string(x)
encode(x::Quantity) = encode(deunitfy(x))
encode(x::Unitful.Units) = unitlabel(x)
encode(x::AbstractVector) = Any[encode(v) for v in x]
encode(x::Tuple) = encode(collect(x))
encode(x::AbstractDict) = APIDict(string(k) => encode(v) for (k, v) in x)
encode(x::NamedTuple) = encode(Dict(pairs(x)))
encode(c::Config) = APIDict(string(s) => APIDict(string(k) => encodevalue(v) for (k, v) in F) for (s, F) in c)
encode(df::DataFrame) = tablepayload(df)
encode(x) = string(x)

unitof(x) = try unittype(x) catch; nothing end

"""
    encodevalue(x, unit=nothing; type=nothing) -> {"value", "type", "unit"}

Encode a scalar (or array) as a value object that keeps its unit. When `unit`
is given the value is converted to it first. `type` names the type a client
should send back (a parameter's declared type); it defaults to the type of the
encoded value.
"""
encodevalue(x, unit=nothing; type=nothing) = begin
    u = isnothing(unit) ? unitof(x) : unit
    raw = hasunit(u) ? deunitfy(x, u) : deunitfy(x)
    APIDict("value" => encode(raw), "type" => isnothing(type) ? wiretype(typeof(raw)) : type, "unit" => unitlabel(u))
end

"""
    tablepayload(df; model=nothing, elapsed=nothing)

Encode a `DataFrame` as `columns` (name, type, unit) plus `rows` of plain values.
"""
tablepayload(df::DataFrame; model=nothing, elapsed=nothing) = begin
    N = DataFrames.names(df)
    plain = [deunitfy(df[!, n]) for n in N]
    columns = [
        APIDict("name" => n, "type" => wiretype(eltype(p)), "unit" => unitlabel(unitof(df[!, n])))
        for (n, p) in zip(N, plain)
    ]
    rows = [Any[encode(p[i]) for p in plain] for i in 1:nrow(df)]
    payload = APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "columns" => columns,
        "rows" => rows,
        "summary" => APIDict("nrow" => nrow(df)),
    )
    isnothing(model) || (payload["model"] = model)
    isnothing(elapsed) || (payload["summary"]["elapsed_ms"] = round(Int, elapsed * 1000))
    payload
end

tojson(x) = JSON.json(encode(x))
