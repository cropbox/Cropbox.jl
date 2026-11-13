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
using TimeZones: TimeZones, TimeZone, ZonedDateTime, astimezone
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

"Reject the fields of object `d` outside `allowed`, so that a misspelled field is not silently ignored."
checkkeys(d::AbstractDict, allowed, what) = begin
    for k in keys(d)
        k in allowed || apierror("Unknown field `$k` in $what; expected $(join(allowed, ", "))")
    end
    d
end

# --- units and scalar types ---------------------------------------------------

const SUPERSCRIPTS = Dict('⁻' => '-', '⁺' => '+', '⁰' => '0', '¹' => '1', '²' => '2', '³' => '3', '⁴' => '4', '⁵' => '5', '⁶' => '6', '⁷' => '7', '⁸' => '8', '⁹' => '9')

"""
    parseunit(s) -> Unitful.Units

Parse a unit label such as `"m"`, `"K*d"`, `"μmol/(m^2*s)"` or `"m s⁻¹"` with
`Unitful.uparse`, which accepts only unit names and the arithmetic operators
(`*`, `/`, `^`, `√`, `+`, `-`, `//`) and rejects any other call or syntax.
Returns `nothing` for `nothing` or a blank string.
"""
parseunit(::Nothing) = nothing
parseunit(u::Unitful.Units) = u
parseunit(s::AbstractString) = begin
    t = strip(s)
    isempty(t) && return nothing
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

"""
Unit label that `parseunit` accepts back: `K*d`, `m*s^-1`, `kPa^(1//2)`, `°C`;
`nothing` when unitless. Exponents are written in ASCII on every platform.
"""
unitlabel(u) = hasunit(u) ? replace(sprint(print, u; context=:fancy_exponent => false),
    " " => "*", r"\^(-?\d+)/(\d+)" => s"^(\1//\2)", "%" => "percent") : nothing

const API_TYPES = Dict{String,Type}(
    "Bool" => Bool, "Int" => Int, "Int64" => Int, "Float64" => Float64, "Float32" => Float64,
    "String" => String, "Symbol" => Symbol, "Date" => Date, "DateTime" => DateTime, "ZonedDateTime" => ZonedDateTime,
)
const TEMPORAL_TYPES = ("Date", "DateTime", "ZonedDateTime")

"Scalar type converted on input for a type name; other names (`Vector{Float64}`, `Any`) leave values as parsed."
apitype(::Nothing) = nothing
apitype(s::AbstractString) = get(API_TYPES, s, nothing)
apitype(s) = apierror("`type` must be a string, got `$s`")

"Type of a value or column given its `type` and `timezone` fields: a time zone alone means zoned times."
scalartype(kind, timezone) = isnothing(kind) && !isnothing(timezone) ? ZonedDateTime : apitype(kind)

"""
Type name under which encoded values of type `T` read back, without its module
(`DateTime`): rationals travel as floats; `missing` and `nothing` have none.
"""
wiretype(T::Type) = begin
    N = nonmissingtype(T)
    N in (Union{}, Nothing) && return nothing
    N <: Rational && return "Float64"
    N isa DataType && isempty(N.parameters) ? string(nameof(N)) : string(N)
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
    checkkeys(d, ("value", "unit", "type", "timezone"), "a value object")
    timezone = get(d, "timezone", nothing)
    v = decodetyped(d["value"], scalartype(kind, timezone); timezone)
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

decodezoned(v::ZonedDateTime, timezone) = isnothing(timezone) ? v : astimezone(v, zone(timezone))
decodezoned(v::DateTime, timezone) = isnothing(timezone) ?
    apierror("ZonedDateTime values without an offset require `timezone` metadata") :
    ZonedDateTime(v, zone(timezone))
decodezoned(v, timezone) = begin
    s = String(v)
    parsed = try ZonedDateTime(s) catch; nothing end
    isnothing(parsed) || return decodezoned(parsed, timezone)
    isnothing(timezone) && apierror("ZonedDateTime value `$s` requires an offset or `timezone` metadata")
    ZonedDateTime(DateTime(s), zone(timezone))
end

# A time zone by its IANA name (`Asia/Seoul`) or offset (`UTC+9`); the name is looked up in the time zone database as it is.
zone(name) = name isa AbstractString && occursin(r"^[A-Za-z0-9_+:-]+(/[A-Za-z0-9_+-]+)*$", name) ? TimeZone(name) : apierror("Invalid time zone `$name`")

"Name of the zone of a `ZonedDateTime` whose offset changes over the year, which its ISO string does not carry."
zonename(x::ZonedDateTime) = (z = TimeZones.timezone(x); z isa TimeZones.VariableTimeZone ? string(z) : nothing)
zonename(x) = nothing

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
takes row arrays, so that the table of a response can be sent back as it is.
Optional `columns` metadata (`name`, `type`, `unit`, `timezone`) converts and
unitfies columns. CSV headers may alternatively carry `name (unit)` or
`name (:Type)` annotations when no `columns` are given. Column names are
unique and a row has no more cells than there are columns, so that no value is
dropped; a cell that is absent or `null` is `missing`.
"""
decodetable(d::AbstractDict) = begin
    checkkeys(d, TABLE_KEYS, "a table")
    columns = [checkkeys(asobject(c), ("name", "type", "unit", "timezone"), "a table column") for c in something(get(d, "columns", nothing), [])]
    all(c -> get(c, "name", nothing) isa AbstractString, columns) || apierror("Every table column requires a `name`")
    allunique(c["name"] for c in columns) || apierror("Table column names must be unique")
    df = if d["type"] == "CSV"
        get(d, "content", nothing) isa AbstractString || apierror("CSV payload requires `content`")
        decodecsv(String(d["content"]), columns)
    else
        isempty(columns) && apierror("DataFrame payload requires `columns`")
        rows = something(get(d, "rows", nothing), [])
        rows isa AbstractVector && all(r -> r isa AbstractVector, rows) || apierror("DataFrame payload `rows` must be an array of row arrays")
        all(r -> length(r) <= length(columns), rows) || apierror("A table row has more cells than the $(length(columns)) `columns`")
        df = DataFrame()
        for (i, c) in enumerate(columns)
            # absent and `null` cells are `missing`, which plotting and evaluation skip
            df[!, Symbol(c["name"])] = samenumbers([length(r) >= i && !isnothing(r[i]) ? r[i] : missing for r in rows])
        end
        applycolumns!(df, columns)
    end
    # Cropbox reads a trailing `(...)` of a column name as a unit or type expression and evaluates it
    for n in DataFrames.names(df)
        endswith(rstrip(n), ')') && apierror("Column name `$n` must not end in parentheses; units and types go in `columns`")
    end
    df
end

const TABLE_KEYS = ("type", "content", "filename", "columns", "rows", "status", "contract_version", "model", "summary")

# JSON writes `1.0` as `1`, so a column of numbers may arrive as integers and floats mixed: read it as floats.
samenumbers(column) = begin
    isconcretetype(nonmissingtype(eltype(column))) && return column
    all(x -> ismissing(x) || (x isa Real && !(x isa Bool)), column) ? [ismissing(x) ? x : float(x) for x in column] : column
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
        timezone = get(c, "timezone", nothing)
        T = scalartype(get(c, "type", nothing), timezone)
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
mixed: nested `{"System": {"name": value}}` and flat `{"System.name": value}`,
where the system may carry its modules (`Main.Plant.Leaf.a`) to tell it from a
namesake. Values are decoded with `value` (scalars, `{value, unit}` objects or tables).
A key without a dot whose object looks like a value or a table is rejected as
a missing system name rather than read as a system.
"""
decodeconfig(::Nothing; value=decode) = configure()
decodeconfig(c::Config; value=decode) = c
decodeconfig(x::AbstractDict; value=decode) = begin
    d = stringkeys(x)
    P = Pair[]
    for (k, v) in d
        # an object that is neither a value nor a table holds the parameters of a system, which may be named with its
        # modules (`{"Main.M.Leaf": {"a": 1}}`, as a calibration answers); anything else under a dotted key is a value
        if v isa AbstractDict && !haskey(v, "value") && !(get(v, "type", nothing) in ("CSV", "DataFrame"))
            push!(P, Symbol(k) => OrderedDict{Symbol,Any}(Symbol(n) => value(w) for (n, w) in v))
        elseif occursin('.', k)
            push!(P, String(k) => value(v))
        else
            apierror("Configuration key `$k` must be a `System.name` path or a system name holding an object of parameters")
        end
    end
    isempty(P) ? configure() : configure(P...)
end
decodeconfig(x; value=decode) = apierror("Configuration must be an object")

"Rows given as nested arrays as a `Matrix`."
asmatrix(rows::AbstractVector) = begin
    allequal(length.(rows)) || apierror("Matrix rows must have the same length")
    permutedims(reduce(hcat, rows))
end

"Convert a flat or nested configuration into `path => value` pairs with `System.name` paths."
flatconfig(c::Config) = ["$(s).$(k)" => v for (s, F) in c for (k, v) in F]

"""Parameter bounds for calibration: `[lo, hi]` or `{"lower": lo, "upper": hi, "unit": "m"}`."""
decodebounds(x::AbstractVector) = begin
    length(x) == 2 || apierror("Parameter range must contain two bounds")
    numericbounds(decode(x[1]), decode(x[2]))
end
decodebounds(x::AbstractDict) = begin
    d = checkkeys(stringkeys(x), ("lower", "upper", "unit"), "a parameter range")
    u = parseunit(get(d, "unit", nothing))
    bound(k) = (b = decode(get(d, k, nothing)); isnothing(u) ? b : unitfy(b, u))
    numericbounds(bound("lower"), bound("upper"))
end
decodebounds(x) = apierror("Unsupported parameter range `$x`")
numericbounds(lower, upper) = lower isa Number && upper isa Number ? (lower, upper) : apierror("Parameter range requires numeric lower and upper bounds")

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
become ISO strings, a matrix becomes an array of row arrays, `Config` becomes
nested objects of value objects and `DataFrame` becomes a table payload.
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
encode(x::AbstractMatrix) = Any[encode(collect(r)) for r in eachrow(x)]
encode(x::Tuple) = encode(collect(x))
encode(x::Pair) = Any[encode(x.first), encode(x.second)]
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
encoded value. A zoned time also carries the name of its `timezone`.
"""
encodevalue(x, unit=nothing; type=nothing) = begin
    u = isnothing(unit) ? unitof(x) : unit
    raw = hasunit(u) ? deunitfy(x, u) : deunitfy(x)
    value = APIDict("value" => encode(raw), "type" => isnothing(type) ? wiretype(typeof(raw)) : type, "unit" => unitlabel(u))
    isnothing(zonename(raw)) || (value["timezone"] = zonename(raw))
    value
end

"""
    tablepayload(df; model=nothing, elapsed=nothing)

Encode a `DataFrame` as a table: `columns` (name, type, unit) plus `rows` of
plain values, in the shape `decodetable` reads.
"""
tablepayload(df::DataFrame; model=nothing, elapsed=nothing) = begin
    N = DataFrames.names(df)
    plain = [deunitfy(df[!, n]) for n in N]
    columns = map(N, plain) do n, p
        column = APIDict("name" => n, "type" => wiretype(eltype(p)), "unit" => unitlabel(unitof(df[!, n])))
        # a column in one zone keeps its name, which the offsets of its values do not tell
        zones = nonmissingtype(eltype(p)) <: ZonedDateTime ? unique(zonename(x) for x in skipmissing(p)) : []
        length(zones) == 1 && !isnothing(only(zones)) && (column["timezone"] = only(zones))
        column
    end
    payload = APIDict(
        "status" => "ok",
        "contract_version" => API_CONTRACT_VERSION,
        "type" => "DataFrame",
        "columns" => columns,
        "rows" => [Any[encode(p[i]) for p in plain] for i in 1:nrow(df)],
        "summary" => APIDict("nrow" => nrow(df)),
    )
    isnothing(model) || (payload["model"] = model)
    isnothing(elapsed) || (payload["summary"]["elapsed_ms"] = round(Int, elapsed * 1000))
    payload
end
