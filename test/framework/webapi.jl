using DataFrames
using Dates
using JSON
using TimeZones

# a system outside `Main`, where `calibrate` cannot look up units by system name
module WebAPITestModels
using Cropbox
@system SWebGrowth(Controller) begin
    r: rate => 1 ~ preserve(parameter, u"cm/hr")
    h(r): height ~ accumulate(u"cm")
end

# systems that a model produces without declaring their type, or declaring only their kind
abstract type SWebFamily <: Cropbox.System end
@system SWebChild <: SWebFamily begin
    c => 1 ~ preserve(parameter, u"m")
end
@system SWebFamilies(Controller) begin
    kids(config) => produce(SWebChild; config) ~ produce::SWebFamily[]
end
@system SWebUntyped(Controller) begin
    kids(config) => produce(SWebChild; config) ~ produce
end
childtype() = SWebChild
@system SWebComputed(Controller) begin
    kids(config) => produce(childtype(); config) ~ produce
end

# two systems of one name from different modules in one model
module NamesakeA
using Cropbox
@system SWebTwin begin
    a => 1 ~ preserve(parameter)
end
end
module NamesakeB
using Cropbox
@system SWebTwin begin
    a => 2 ~ preserve(parameter)
end
end
@system SWebTwins(Controller) begin
    x(context) ~ ::NamesakeA.SWebTwin
    y(context) ~ ::NamesakeB.SWebTwin
end

# and two whose modules share a name, so that `Shared.SWebLeaf` reaches both; `lower` is also a key of a range
module SharedA
module Shared
using Cropbox
@system SWebLeaf begin
    a => 1 ~ preserve(parameter)
    lower => 1 ~ preserve(parameter)
end
end
end
module SharedB
module Shared
using Cropbox
@system SWebLeaf begin
    a => 2 ~ preserve(parameter)
    lower => 1 ~ preserve(parameter)
end
end
end
@system SWebLeaves(Controller) begin
    x(context) ~ ::SharedA.Shared.SWebLeaf
    y(context) ~ ::SharedB.Shared.SWebLeaf
end

# a parameter shared through a mixin: by systems produced while the model runs, and by one that counts it in integers
@system SWebShared begin
    k => 2 ~ preserve(parameter)
end
@system SWebKid(SWebShared) begin
    n => 1 ~ preserve(parameter)
end
kidtype() = SWebKid
@system SWebOpen(SWebShared, Controller) begin
    kids(config) => produce(kidtype(); config) ~ produce
end
@system SWebWhole(SWebShared) begin
    k => 2 ~ preserve::int(parameter)
end
@system SWebMixed(SWebShared, Controller) begin
    whole(context) ~ ::SWebWhole
end
end

@testset "webapi" begin
    @system SWebAPI(Controller) begin
        "Plant length."
        a: length => 1 ~ preserve(parameter, u"m")
        "Reported length."
        b(a) => a ~ track(u"m")
        c => 2 ~ preserve(parameter)
        f => true ~ preserve::Bool(parameter)
        n => 3 ~ preserve::Int(parameter)
        d(a) => 2a ~ preserve(u"m", parameter)
        g(b) => b > 1.5u"m" ~ flag
    end

    @system SWebTable{Context => Cropbox.DailyContext}(Controller) begin
        weather ~ provide(parameter)
        T: temperature ~ drive(from=weather, by=:tavg, u"°C")
    end

    # a nested system and a mixin: access paths, declaring systems and aliases differ from the flat case
    @system SWebLeaf begin
        "Leaf area."
        area: A => 2 ~ preserve(parameter, u"cm^2")
        doubled(area) => 2area ~ track(u"cm^2")
    end

    @system SWebRate begin
        k: rate => 1 ~ preserve(parameter)
    end

    # a mixin has to exist when the macro expands
    @eval @system SWebPlant(SWebRate, Controller) begin
        leaf(context) ~ ::SWebLeaf
        total(x=leaf.doubled, k) => k * x ~ track(u"cm^2")
        shares => [0.25 0.75; 0.5 0.5] ~ tabulate(rows=(:early, :late), columns=(:leaf, :root), parameter)
        late_root(shares) => shares[:late].root ~ track
    end

    # a system that only exists once the model produces it
    @system SWebSeed begin
        mass => 1 ~ preserve(parameter, u"g")
    end

    @eval @system SWebPod(Controller) begin
        seeds => produce(SWebSeed) ~ produce::SWebSeed[]
    end

    # a value the constructor is given rather than a parameter, and a model that fails when it runs
    @system SWebExternal(Controller) begin
        a    ~ preserve(extern)
        x(a) ~ track
    end

    @system SWebBroken(Controller) begin
        x => error("broken") ~ track
    end

    @testset "produced systems" begin
        M = WebAPITestModels
        # the systems a `produce` declares only by kind, or not at all, are those its body passes to `produce`
        for S in (M.SWebFamilies, M.SWebUntyped)
            index = Cropbox.ModelIndex(S)
            @test haskey(index.parameters, "SWebChild.c") && isempty(index.open)
            # describing them follows the systems found once, with no second walk into the open declaration
            d = describe(S)
            @test only(filter(p -> p["path"] == "SWebChild.c", d["parameters"]))["default"]["value"] == 1
            @test Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebChild.c" => 2)); index)[:config] == @config(:SWebChild => :c => 2)
            service = Cropbox.Service(S; dashboard = :none)
            @test Cropbox.respond(service, "POST", "/api/simulate", JSON.json(Dict("config" => Dict("SWebChild.c" => 2), "stop" => 1)))[1] == 200
        end
        # a system computed while the model runs cannot be checked, and the rejection says why
        index = Cropbox.ModelIndex(M.SWebComputed)
        @test index.open == ["SWebComputed.kids"] && !haskey(index.parameters, "SWebChild.c")
        e = try Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebChild.c" => 2)); index) catch e; e end
        @test e isa Cropbox.APIRequestError && occursin("`SWebComputed.kids`", e.message) && occursin("only known once the model runs", e.message)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebComputed.nope" => 2)); index)
    end

    weather_csv = "index (d),tavg (°C)\n0,10\n1,12\n2,14\n"
    weather_table = Dict("type" => "CSV", "content" => weather_csv)

    @testset "describe" begin
        @test describe(DataFrame(a = [1])) isa DataFrame
        d = describe(SWebAPI)
        @test d["contract"]["version"] == Cropbox.API_CONTRACT_VERSION == "0.2.0"
        @test d["model"]["name"] == "SWebAPI"
        @test only(d["systems"])["name"] == "SWebAPI" && only(d["systems"])["root"]
        P = Dict(p["name"] => p for p in d["parameters"])
        @test Set(keys(P)) == Set(["a", "c", "f", "n", "d"])
        a = P["a"]
        @test a["path"] == a["declared"] == "SWebAPI.a"
        @test a["target"] == "a" && a["alias"] == "length"
        @test a["unit"] == "m" && a["type"] == "Float64" && a["role"] == "parameter"
        @test a["default"] == Dict("value" => 1, "type" => "Float64", "unit" => "m")
        @test a["description"] == "Plant length."
        @test P["c"]["unit"] === nothing && P["c"]["default"]["value"] == 2
        @test P["f"]["type"] == "Bool" && P["f"]["default"]["value"] === true
        @test P["n"]["type"] == "Int" && P["n"]["default"]["value"] == 3
        @test P["d"]["type"] == "Float64" && P["d"]["default"]["value"] === nothing && P["d"]["default"]["unit"] == "m"
        V = Dict(v["name"] => v for v in d["variables"])
        @test V["b"]["dependencies"] == ["a"] && V["b"]["role"] == "output" && V["b"]["state"] == "track"
        @test V["g"]["type"] == "Bool" && V["g"]["role"] == "output"
        @test !haskey(V, "a")
        @test isempty(d["tables"])
        index = Cropbox.ModelIndex(SWebAPI)
        @test issubset(["a", "b", "*", "context.clock.time", "context.clock.*"], index.paths) && index.aliases["length"] == "a"
        @test only(index.parameters["SWebAPI.a"]) === only(index.parameters["SWebAPI.length"]) === only(index.parameters["Controller.a"])
        @test only(index.parameters["SWebAPI.a"]).type == "Float64" && only(index.parameters["Clock.step"]).type == "Rational{Int64}"
        @test !haskey(index.parameters, "SWebAPI.b")

        configured = describe(SWebAPI; config = :SWebAPI => :a => 300u"cm")
        @test only(filter(p -> p["name"] == "a", configured["parameters"]))["default"]["value"] == 3

        vars = Cropbox.variables(SWebAPI)
        @test all(v -> v.info isa Cropbox.VarInfo, vars)
        @test only(filter(v -> v.name == :a, vars)).config == "SWebAPI.a"
        @test issubset([:SWebAPI, :Controller, :System], only(filter(v -> v.name == :a, vars)).systems)
        # the context is walked as well, marked as left out of descriptions
        @test [v.target for v in vars if v.excluded && v.name == :step] == ["context.clock.step"] && !any(v -> v.excluded, filter(v -> v.path == "", vars))
        # its parameters are described once the configuration sets them
        clocked = describe(SWebAPI; config = :Clock => :step => 2u"hr")
        @test only(filter(p -> p["path"] == "Clock.step", clocked["parameters"]))["default"] == Dict("value" => 2, "type" => "Rational{Int64}", "unit" => "hr")
        @test all(s -> s["name"] == "SWebAPI", clocked["systems"]) && !any(v -> v["system"] == "Clock", clocked["variables"])

        t = describe(SWebTable)
        table = only(t["tables"])
        @test table["path"] == "SWebTable.weather" && table["role"] == "table" && table["state"] == "provide"
        @test table["index"] == "index"
        @test only(table["columns"]) == Dict("variable" => "T", "name" => "T", "column" => "tavg", "unit" => "°C")
        @test only(filter(p -> p["name"] == "weather", t["parameters"]))["default"] === nothing
        @test only(Cropbox.ModelIndex(SWebTable).parameters["SWebTable.weather"]).role == "table"

        n = describe(SWebPlant)
        @test [(s["name"], s["path"], s["root"]) for s in n["systems"]] == [("SWebPlant", "", true), ("SWebLeaf", "leaf", false)]
        P = Dict(p["path"] => p for p in n["parameters"])
        @test P["SWebPlant.k"]["declared"] == "SWebRate.k" && P["SWebPlant.k"]["alias"] == "rate" && P["SWebPlant.k"]["target"] == "k"
        @test P["SWebLeaf.area"]["target"] == "leaf.area" && P["SWebLeaf.area"]["default"] == Dict("value" => 2, "type" => "Float64", "unit" => "cm^2")
        @test Set(v["target"] for v in n["variables"] if v["role"] == "output") == Set(["total", "leaf.doubled", "late_root"])
        @test P["SWebPlant.shares"]["state"] == "tabulate" && P["SWebPlant.shares"]["default"]["value"] == [[0.25, 0.75], [0.5, 0.5]]
        index = Cropbox.ModelIndex(SWebPlant)
        @test issubset(["SWebPlant.k", "SWebRate.k", "SWebPlant.rate", "SWebRate.rate", "SWebLeaf.area", "SWebLeaf.A"], keys(index.parameters))
        @test only(index.parameters["SWebRate.rate"]).config == "SWebPlant.k"
        @test issubset(["*", "leaf.*", "total", "k", "leaf.area", "leaf.doubled"], index.paths)
        @test index.aliases["rate"] == "k" && index.aliases["leaf.A"] == "leaf.area"

        # a parameter set through an alias or a mixin is described once, with the value in effect
        spelled = describe(SWebPlant; config = (:SWebRate => :rate => 3, :SWebLeaf => :A => 5u"cm^2"))
        @test allunique(p["path"] for p in spelled["parameters"])
        P = Dict(p["path"] => p for p in spelled["parameters"])
        @test P["SWebPlant.k"]["default"]["value"] == 3 && P["SWebLeaf.area"]["default"]["value"] == 5
        # a client value is the one Cropbox reads, whichever spelling the base and the client used
        rate(c) = instance(SWebPlant; config = c).k'
        qualified = Symbol(first(names(SWebPlant)))
        @test rate(Cropbox.override(@config(:SWebPlant => :k => 1), @config(:SWebRate => :rate => 3), index)) == 3
        @test rate(Cropbox.override(@config(qualified => :k => 1), @config(:SWebPlant => :rate => 2), index)) == 2
        @test rate(Cropbox.override(@config(:SWebPlant => :rate => 1), @config(:SWebRate => :k => 4), index)) == 4
        # and nothing of the base goes: a base the client does not shadow stays as it was written
        @test Cropbox.override(@config(:SWebRate => :rate => 3), @config(:SWebLeaf => :A => 1), index) == @config(:SWebRate => :rate => 3, :SWebLeaf => :A => 1)
        @test Cropbox.override((), @config(:Other => :x => 1), index) == @config(:Other => :x => 1)

        # every state that holds a value is an output; a function, a table or a produced system is not
        @system SWebStates(Controller) begin
            t(context.clock.tick) ~ track
            w(t) => t >= 2 ~ flag
            i => -1 ~ preserve
            r(t) ~ remember(init=i, when=w)
            a ~ advance
            lo => 0 ~ preserve
            hi => 1 ~ preserve
            f(hi; x) => hi * x ~ integrate(from=lo, to=hi)
            h(; x) => x ~ call
        end
        roles = Dict(v["name"] => v["role"] for v in describe(SWebStates)["variables"])
        @test all(name -> roles[name] == "output", ["t", "w", "i", "r", "a", "lo", "hi", "f"]) && roles["h"] == "internal"
        @test [v["target"] for v in Cropbox.widgetpayload(SWebStates)["outputs"]] == ["time", "t", "w", "i", "r", "a", "lo", "hi", "f"]

        # produced systems have no fixed path but are configured like the others
        pod = describe(SWebPod)
        @test [(s["name"], s["path"]) for s in pod["systems"]] == [("SWebPod", ""), ("SWebSeed", nothing)]
        mass = only(pod["parameters"])
        @test mass["path"] == "SWebSeed.mass" && mass["target"] === nothing && mass["default"] == Dict("value" => 1, "type" => "Float64", "unit" => "g")
        @test [v["target"] for v in pod["variables"]] == ["seeds"] && haskey(Cropbox.ModelIndex(SWebPod).parameters, "SWebSeed.mass")
    end

    @testset "codec" begin
        @test Cropbox.parseunit("K*d") == u"K*d"
        @test Cropbox.parseunit("m s⁻¹") == u"m/s"
        @test Cropbox.parseunit("μmol/mol") == u"μmol/mol" && Cropbox.parseunit("μmol/(m^2*s)") == u"μmol/m^2/s"
        @test Cropbox.parseunit("") === nothing && Cropbox.parseunit(nothing) === nothing
        @test_throws Cropbox.APIRequestError Cropbox.parseunit("Base.eval")
        # only unit names and arithmetic: no other call, no quantity
        for bad in ("exit(1)", "run(`true`)", "m[1]", "1.5*m", "(m, s)")
            @test_throws Cropbox.APIRequestError Cropbox.parseunit(bad)
        end
        @test_throws Cropbox.APIRequestError Cropbox.parseunit("nounit")
        for u in (u"m", u"K*d", u"μmol/mol", u"°C", u"percent", u"m/s^2", u"μmol/m^2/s", u"kPa^(1//2)")
            @test Cropbox.parseunit(Cropbox.unitlabel(u)) == u
        end
        # labels are the same on every platform
        @test Cropbox.unitlabel(u"cm^2") == "cm^2" && Cropbox.unitlabel(u"m/s") == "m*s^-1" && Cropbox.unitlabel(u"kPa^(1//2)") == "kPa^(1//2)"
        @test Cropbox.unitlabel(Cropbox.Unitful.NoUnits) === nothing && Cropbox.unitlabel(nothing) === nothing

        @test Cropbox.decode(Dict("value" => 200, "unit" => "cm")) == 200u"cm"
        @test Cropbox.decode(Dict("value" => "2024-01-02", "type" => "Date")) == Date(2024, 1, 2)
        @test Cropbox.decode(Dict("value" => "2024-01-02T03:00:00", "type" => "ZonedDateTime", "timezone" => "Asia/Seoul")) == ZonedDateTime(2024, 1, 2, 3, tz"Asia/Seoul")
        @test Cropbox.decode(Dict("value" => "2024-01-02T03:00:00+09:00", "type" => "ZonedDateTime")) == ZonedDateTime(2024, 1, 2, 3, tz"Asia/Seoul")
        @test Cropbox.decode(Dict("value" => "x", "type" => "Symbol")) == :x
        @test Cropbox.decode(Dict("value" => "2.5", "type" => "Float64")) == 2.5
        @test Cropbox.decode([1, Dict("value" => 2, "unit" => "m")]) == [1, 2u"m"]
        @test Cropbox.decode("text") == "text" && Cropbox.decode(nothing) === nothing
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("value" => "2024-01-02T03:00:00", "type" => "ZonedDateTime"))
        @test Cropbox.decode(Dict("value" => [1, 2.5], "type" => "Float64", "unit" => "m")) == [1.0, 2.5]u"m"
        # type names that are not convertible scalars leave the value as parsed
        @test Cropbox.decode(Dict("value" => 1, "type" => "Matrix")) == 1 && Cropbox.decode(Dict("value" => [1, 2], "type" => "Vector{Int64}")) == [1, 2]
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("value" => 1, "type" => 5))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("unit" => "m"))
        # a misspelled field is not silently dropped
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("value" => 1, "units" => "m"))
        @test Cropbox.parsebool("yes") === true && Cropbox.parsebool("off") === false && Cropbox.parsebool(1) === true
        # a zone whose offset changes over the year travels by name
        seoul, newyork = ZonedDateTime(2024, 1, 2, 3, tz"Asia/Seoul"), ZonedDateTime(2024, 1, 2, 3, tz"America/New_York")
        @test Cropbox.encodevalue(newyork) == Dict("value" => "2024-01-02T03:00:00-05:00", "type" => "ZonedDateTime", "unit" => nothing, "timezone" => "America/New_York")
        @test TimeZones.timezone(Cropbox.decode(Cropbox.encodevalue(newyork))) == tz"America/New_York"
        @test Cropbox.decode(Dict("value" => "2024-01-02T03:00:00", "timezone" => "Asia/Seoul")) == seoul
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("value" => "2024-01-02T03:00:00", "timezone" => "../etc/passwd"))

        df = Cropbox.decode(weather_table)
        @test df isa DataFrame && names(df) == ["index", "tavg"]
        @test df.index == [0, 1, 2]u"d" && df.tavg == [10, 12, 14]u"°C"
        typed = Cropbox.decode(Dict("type" => "CSV", "content" => "t,v\n2024-01-01T00:00:00,1.5\n",
            "columns" => [Dict("name" => "t", "type" => "ZonedDateTime", "timezone" => "Asia/Seoul"), Dict("name" => "v", "type" => "Float64", "unit" => "m")]))
        @test typed.t == [ZonedDateTime(2024, 1, 1, tz"Asia/Seoul")] && typed.v == [1.5u"m"]
        rows = Cropbox.decode(Dict("type" => "DataFrame", "columns" => [Dict("name" => "time", "unit" => "hr"), Dict("name" => "b", "unit" => "m")], "rows" => [[0, 1], [1, 2]]))
        @test rows.time == [0, 1]u"hr" && rows.b == [1, 2]u"m"
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "t,v\n1,2\n", "columns" => [Dict("name" => "t", "type" => "Date", "unit" => "d")]))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => weather_csv, "columns" => [Dict("name" => "index")]))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "a (:Vector),b\n1,2\n"))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "a (nounit)\n1\n"))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "DataFrame", "columns" => [Dict("name" => "a (m)")], "rows" => []))
        # a second annotation would reach Cropbox, which evaluates what a column name carries in parentheses
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "index (d),tavg(:Date) (°C)\n0,10\n"))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "a,b\n1,2\n", "colums" => []))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "a,b\n1,2\n", "columns" => [Dict("name" => "a", "units" => "m")]))
        # JSON numbers of one column are read alike
        mixed = Cropbox.decode(JSON.parse("""{"type": "DataFrame", "columns": [{"name": "t", "unit": "hr"}, {"name": "n"}, {"name": "s"}], "rows": [[0, 1, "a"], [0.5, 2, 1], [1, null, "c"]]}"""))
        @test eltype(mixed.t) == typeof(1.0u"hr") && eltype(mixed.n) == Union{Missing,Int} && mixed.s == ["a", 1, "c"]
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV"))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "DataFrame", "columns" => [Dict("name" => "a")], "rows" => [Dict("a" => 1)]))
        # no value is dropped: column names are unique and a row has no more cells than there are columns
        ab = [Dict("name" => "a"), Dict("name" => "b")]
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "DataFrame", "columns" => [Dict("name" => "a"), Dict("name" => "a")], "rows" => [[1, 100], [2, 200]]))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "DataFrame", "columns" => ab, "rows" => [[0, 1, 999], [1, 2, 888]]))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV", "content" => "a,b\n1,2\n", "columns" => [Dict("name" => "a"), Dict("name" => "a")]))
        short = Cropbox.decode(Dict("type" => "DataFrame", "columns" => ab, "rows" => [[0], [1, 2]]))
        @test short.a == [0, 1] && ismissing(short.b[1]) && short.b[2] == 2

        flat = Cropbox.decodeconfig(Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm"), "SWebAPI.c" => 3))
        nested = Cropbox.decodeconfig(Dict("SWebAPI" => Dict("a" => Dict("value" => 200, "unit" => "cm"), "c" => 3)))
        @test flat == nested == @config(:SWebAPI => (a = 200u"cm", c = 3))
        @test Cropbox.decodeconfig(nothing) == @config()
        @test Cropbox.decodeconfig(flat) === flat
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig([Dict("path" => "SWebAPI.a", "value" => 1)])
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig(Dict("a" => 1))
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig(Dict("a" => Dict("value" => 1, "unit" => "m")))
        # a flat path may name the system with its modules; only the model says whether it has one
        @test Cropbox.decodeconfig(Dict("Model.SWebAPI.a" => 1)) == @config(Symbol("Model.SWebAPI") => :a => 1)
        # and so may the system of a nested object, as a calibration answers
        @test Cropbox.decodeconfig(Dict("Model.SWebAPI" => Dict("a" => 1))) == @config(Symbol("Model.SWebAPI") => :a => 1)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("Model.SWebAPI.a" => 1)); index = Cropbox.ModelIndex(SWebAPI))
        @test Cropbox.decodeconfig(Dict("Soil" => Dict("type" => "clay"))) == @config(:Soil => :type => "clay")
        @test Dict(Cropbox.flatconfig(flat)) == Dict("SWebAPI.a" => 200u"cm", "SWebAPI.c" => 3)
        decoderanges(x) = Cropbox.decodeconfig(x; value = Cropbox.decodebounds, isvalue = Cropbox.israngeobject)
        bounds = decoderanges(Dict("SWebAPI.a" => [1, 2], "SWebAPI" => Dict("c" => Dict("lower" => 0, "upper" => 1, "unit" => "m"))))
        @test bounds[:SWebAPI][:a] == (1, 2) && bounds[:SWebAPI][:c] == (0u"m", 1u"m")
        # a range object under a flat path is a value, while one under a module-qualified system holds its parameters
        ranged = decoderanges(Dict("SWebAPI.c" => Dict("lower" => 0, "upper" => 1), "Main.SWebAPI" => Dict("a" => Dict("lower" => 1, "upper" => 2))))
        @test ranged[:SWebAPI][:c] == (0, 1) && ranged[Symbol("Main.SWebAPI")][:a] == (1, 2)
        # parameters named like the keys of a range hold ranges, and values outside calibration are never ranges
        @test decoderanges(Dict("Main.SWebAPI" => Dict("lower" => [0, 1], "unit" => Dict("lower" => 2, "upper" => 3))))[Symbol("Main.SWebAPI")] == Dict(:lower => (0, 1), :unit => (2, 3))
        @test Cropbox.decodeconfig(Dict("Main.SWebAPI" => Dict("lower" => 1.5, "upper" => 2)))[Symbol("Main.SWebAPI")] == Dict(:lower => 1.5, :upper => 2)
        @test Cropbox.decodebounds(Dict("lower" => Dict("value" => 1, "unit" => "cm"), "upper" => Dict("value" => 2, "unit" => "cm"))) == (1u"cm", 2u"cm")
        @test_throws Cropbox.APIRequestError Cropbox.decodebounds([1])
        @test_throws Cropbox.APIRequestError Cropbox.decodebounds(Dict("lower" => 0))
        @test_throws Cropbox.APIRequestError Cropbox.decodebounds(Dict("min" => 0, "max" => 1))
        @test Dict(pairs(Cropbox.decodeoptions(Dict("MaxSteps" => 4, "Method" => "xnes")))) == Dict(:MaxSteps => 4, :Method => :xnes)
        @test Cropbox.decodeoptions(()) == (;) && Cropbox.decodeoptions(nothing) == (;)
        @test Cropbox.asobject(nothing) == Cropbox.asobject(()) == Cropbox.APIDict() && Cropbox.asobject((a = nothing,)) == Dict("a" => nothing)
        @test_throws Cropbox.APIRequestError Cropbox.asobject("x")
        @test Cropbox.decode([1, nothing, Dict("value" => 2, "unit" => "m")]) == [1, nothing, 2u"m"]

        @test Cropbox.encode(NaN) === nothing && Cropbox.encode(Inf) === nothing && Cropbox.encode(missing) === nothing
        @test Cropbox.encode(1 // 2) == 0.5 && Cropbox.encode(:x) == "x" && Cropbox.encode(Date(2024, 1, 2)) == "2024-01-02"
        @test Cropbox.encode(2u"m") == 2 && Cropbox.encode([1u"m", 2u"m"]) == [1, 2]
        @test Cropbox.encode([1 2; 3 4]) == [[1, 2], [3, 4]] && Cropbox.encode(:a => 1) == ["a", 1]
        @test Cropbox.asmatrix([[1, 2], [3, 4]]) == [1 2; 3 4]
        @test_throws Cropbox.APIRequestError Cropbox.asmatrix([[1, 2], [3]])
        @test Cropbox.encodevalue(2u"m") == Dict("value" => 2, "type" => "Int64", "unit" => "m")
        @test Cropbox.encodevalue(2u"m", u"cm") == Dict("value" => 200, "type" => "Int64", "unit" => "cm")
        @test Cropbox.encodevalue(2.5) == Dict("value" => 2.5, "type" => "Float64", "unit" => nothing)
        @test Cropbox.encodevalue(missing, u"m") == Dict("value" => nothing, "type" => nothing, "unit" => "m")
        @test Cropbox.encodevalue(1 // 2) == Dict("value" => 0.5, "type" => "Float64", "unit" => nothing)
        @test Cropbox.encodevalue(1u"m"; type = "Float64") == Dict("value" => 1, "type" => "Float64", "unit" => "m")
        @test Cropbox.wiretype(Union{Missing,Float64}) == "Float64" && Cropbox.wiretype(Missing) === nothing
        @test Cropbox.encode(@config(:S => :a => 1u"m")) == Dict("S" => Dict("a" => Dict("value" => 1, "type" => "Int64", "unit" => "m")))
        payload = Cropbox.tablepayload(DataFrame(t = [0, 1]u"hr", v = [1.5, NaN], s = [:x, :y]); model = "M")
        @test payload["status"] == "ok" && payload["model"] == "M" && payload["summary"]["nrow"] == 2 && payload["type"] == "DataFrame"
        @test payload["columns"] == [Dict("name" => "t", "type" => "Int64", "unit" => "hr"), Dict("name" => "v", "type" => "Float64", "unit" => nothing), Dict("name" => "s", "type" => "Symbol", "unit" => nothing)]
        @test payload["rows"] == [[0, 1.5, "x"], [1, nothing, "y"]]
        @test JSON.parse(JSON.json(payload))["rows"][2][2] === nothing
        # a response is itself a table that can be sent back
        roundtrip = Cropbox.decode(JSON.parse(JSON.json(payload)))
        @test roundtrip.t == [0, 1]u"hr" && roundtrip.v[1] == 1.5 && ismissing(roundtrip.v[2]) && roundtrip.s == [:x, :y]
        zoned = Cropbox.tablepayload(DataFrame(t = [newyork, newyork + Day(200)]))
        @test only(zoned["columns"]) == Dict("name" => "t", "type" => "ZonedDateTime", "unit" => nothing, "timezone" => "America/New_York")
        @test Cropbox.decode(JSON.parse(JSON.json(zoned))).t == [newyork, newyork + Day(200)] && TimeZones.timezone(Cropbox.decode(zoned).t[2]) == tz"America/New_York"
    end

    @testset "requests" begin
        index = Cropbox.ModelIndex(SWebAPI)
        r = Dict{String,Any}(
            "config" => Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm")),
            "stop" => Dict("value" => 1, "unit" => "hr"), "target" => ["a", "b"], "index" => "time",
            "seed" => 7, "nounit" => "true",
        )
        kw = Cropbox.simulationkwargs(r; index)
        @test kw[:config] == @config(:SWebAPI => :a => 200u"cm")
        # `time` as an index is the clock time, which this model has no variable for
        @test kw[:stop] == 1u"hr" && kw[:target] == ["a", "b"] && kw[:index] == (:time => "context.clock.time")
        @test kw[:seed] == 7 && kw[:nounit] === true && !haskey(kw, :options)
        # constructor options are the service's; a request has none
        merged = Cropbox.simulationkwargs(r; config = :SWebAPI => (a = 3u"m", c = 5), options = (y = 2,))
        @test merged[:config] == @config(:SWebAPI => (a = 200u"cm", c = 5)) && merged[:options] == (y = 2,)
        @test_throws Cropbox.APIRequestError Cropbox.requestobject(Dict("target" => "a", "options" => Dict("x" => 1)), :simulate)
        multi = Cropbox.simulationkwargs(Dict{String,Any}("configs" => [Dict("SWebAPI.a" => 1), Dict("SWebAPI.a" => 2)]); config = :SWebAPI => :c => 5)
        @test multi[:configs] == [@config(:SWebAPI => (a = 1, c = 5)), @config(:SWebAPI => (a = 2, c = 5))] && !haskey(multi, :config)
        @test Cropbox.simulationkwargs(Dict{String,Any}("stop" => "g", "target" => Dict("len" => "length")); index)[:target] == [:len => "length"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("stop" => "nope"); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("target" => ["a", "zzz"]); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("target" => 5); index)
        # indexed and bundle paths only resolve at run time
        @test Cropbox.simulationkwargs(Dict{String,Any}("target" => "leaves[1].area"); index)[:target] == "leaves[1].area"
        # every configuration is checked, by name or alias
        @test Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.length" => "2.5")); index)[:config] == @config(:SWebAPI => :length => 2.5)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.zzz" => 1)); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("configs" => [Dict("SWebAPI.a" => 1), Dict("SWebAPI.zzz" => 1)]); index)
        # clients set what the model declares: the context and produced systems included, nothing else
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("Other.zzz" => 1)); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("Clock.zzz" => 1)); index)
        step = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("Clock.step" => Dict("value" => 0.5, "unit" => "hr"))); index)[:config][:Clock][:step]
        @test step == (1 // 2)u"hr" && Cropbox.deunitfy(step) isa Rational
        @test Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebSeed.mass" => 2)); index = Cropbox.ModelIndex(SWebPod))[:config] == @config(:SWebSeed => :mass => 2)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.a" => weather_table)); index)
        # a parameter that holds one value takes no array, and a quantity only in a unit it can be converted from
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.a" => [1, 2])); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.a" => Dict("value" => 1, "unit" => "kg"))); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.c" => Dict("value" => 1, "unit" => "m"))); index)
        # a plain value has the declared type: an integer for `Int`, a boolean for `Bool`, a value rather than null
        for (path, x) in (("SWebAPI.n", 1.5), ("SWebAPI.n", nothing), ("SWebAPI.n", true), ("SWebAPI.f", 2), ("SWebAPI.f", nothing), ("SWebAPI.c", true), ("SWebAPI.c", nothing))
            @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict(path => x)); index)
        end
        # the declared type is checked in the declared unit: 1.5 km is 1500 m, 150 cm is no whole number of metres
        @system SWebCount(Controller) begin
            d => 2 ~ preserve::int(parameter, u"m")
        end
        counted = Cropbox.ModelIndex(SWebCount)
        count(x) = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebCount.d" => x)); index = counted)[:config][:SWebCount][:d]
        @test count(Dict("value" => 1.5, "unit" => "km")) == 1500u"m" && count(Dict("value" => 2, "unit" => "km")) == 2000u"m" && count(3) == 3
        for bad in (Dict("value" => 150, "unit" => "cm"), 1e30, Dict("value" => 1e30, "unit" => "m"), 1.5, true)
            @test_throws Cropbox.APIRequestError count(bad)
        end
        @test JSON.parse(Cropbox.respond(Cropbox.Service(SWebCount; dashboard = :none), "POST", "/api/simulate",
            JSON.json(Dict("config" => Dict("SWebCount.d" => Dict("value" => 1.5, "unit" => "km")), "target" => "d", "stop" => 1)))[3])["rows"][1][2] == 1500
        # a path that sets a parameter of several systems has to suit every one of them
        mixed = Cropbox.ModelIndex(WebAPITestModels.SWebMixed)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebShared.k" => 1.5)); index = mixed)
        @test Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebShared.k" => 3)); index = mixed)[:config] == @config(:SWebShared => :k => 3)
        # a base setting that reaches systems the index cannot see stays, beside the client value for the root
        opened = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebOpen.k" => 4));
            config = :SWebShared => :k => 5, index = Cropbox.ModelIndex(WebAPITestModels.SWebOpen))[:config]
        @test Cropbox.option(opened, [:SWebKid, :SWebShared], :k) == 5 && Cropbox.option(opened, names(WebAPITestModels.SWebOpen), :k) == 4
        # `meta` goes by the spelling the configuration used, a mixin name included
        metas = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebRate.rate" => 3), "meta" => "SWebRate"); index = Cropbox.ModelIndex(SWebPlant))
        @test metas[:meta] == :SWebRate
        typed = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.n" => 2.0, "SWebAPI.f" => false, "SWebAPI.c" => 3)); index)[:config][:SWebAPI]
        @test typed[:n] == 2 && typed[:f] === false && typed[:c] == 3
        converted = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.a" => Dict("value" => 250, "unit" => "cm"))); index)[:config][:SWebAPI][:a]
        @test converted == 2.5u"m" && Cropbox.Unitful.unit(converted) == u"m"
        # an empty `configs` runs the single configuration
        @test Cropbox.simulationkwargs(Dict{String,Any}("configs" => []); config = :SWebAPI => :c => 5) == Dict(:config => @config(:SWebAPI => :c => 5))
        @test Cropbox.simulationkwargs(Dict{String,Any}("stop" => true, "snap" => false)) == Dict(:stop => true, :snap => false)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("snap" => 5))
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("stop" => [1, 2]))
        # a quantity for `stop` or `snap` is a duration
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("stop" => Dict("value" => 1, "unit" => "kg")); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("snap" => Dict("value" => 1, "unit" => "m")); index)
        @test Cropbox.simulationkwargs(Dict{String,Any}("stop" => Dict("value" => 2, "unit" => "d"), "snap" => Dict("value" => 30, "unit" => "minute")); index) == Dict(:stop => 2u"d", :snap => 30u"minute")
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("target" => Dict("len" => 5)); index)
        @test Cropbox.simulationkwargs(Dict{String,Any}("index" => ["time", "b"], "target" => "context.clock.tick"); index)[:index] == [:time => "context.clock.time", "b"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("target" => "context.clock.tock"); index)
        @test_throws Cropbox.APIRequestError Cropbox.requestobject(Dict("target" => "a", "config_entries" => []), :simulate)
        @test_throws Cropbox.APIRequestError Cropbox.requestobject(Dict("y" => "a", "seed" => 1), :visualize)
        # `meta` names configured systems or gives constant columns
        configured = Dict{String,Any}("config" => Dict("SWebAPI.a" => 1))
        @test Cropbox.simulationkwargs(merge(configured, Dict("meta" => "SWebAPI")); index)[:meta] == :SWebAPI
        @test Cropbox.simulationkwargs(merge(configured, Dict("meta" => Dict("site" => "A"))); index)[:meta] == [:site => "A"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("meta" => "SWebAPI"); index)
        # trusted Julia values from `request_defaults` pass through
        @test Cropbox.simulationkwargs(Dict{String,Any}("target" => [:a, :b], "snap" => identity); index)[:target] == [:a, :b]
        @test Cropbox.simulationkwargs(Dict{String,Any}("target" => ["zzz"]))[:target] == ["zzz"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(Dict{String,Any}("configs" => Dict("SWebAPI.a" => 1)))
        # a sweep is one configuration per value, set through the parameter's own name
        @test Cropbox.decodestep(Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 3, "step" => 1, "unit" => "m")) == [@config(:SWebAPI => :a => v) for v in (1:3)u"m"]
        @test Cropbox.decodestep(Dict("path" => "SWebAPI.length", "values" => [100, 200], "unit" => "cm"), index) == [@config(:SWebAPI => :a => 100u"cm"), @config(:SWebAPI => :a => 200u"cm")]
        @test Cropbox.decodestep(Dict("path" => "SWebRate.rate", "values" => [1]), Cropbox.ModelIndex(SWebPlant)) == [@config(:SWebPlant => :k => 1)]
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.zzz", "values" => [1]), index)
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebTable.weather", "values" => [1]), Cropbox.ModelIndex(SWebTable))
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "a", "values" => [1]))
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 3))
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("system" => "SWebAPI", "name" => "a", "values" => [1, 2]))
        # its values are checked as those of a configuration are, and there has to be one
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.a", "values" => [1], "unit" => "kg"), index)
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.a", "values" => [[1, 2]]), index)
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.a", "values" => []))
        # every run of a sweep is over the configuration of the request
        swept = Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict("SWebAPI.c" => 5), "xstep" => Dict("path" => "SWebAPI.length", "values" => [1, 2]));
            config = :SWebAPI => :n => 4, index, fields = Cropbox.REQUEST_KEYS.visualize)
        @test swept[:configs] == [@config(:SWebAPI => (n = 4, c = 5, a = 1)), @config(:SWebAPI => (n = 4, c = 5, a = 2))] && !haskey(swept, :config)
        plot = Cropbox.decodeplot(Dict("xlim" => [nothing, 5], "linestyle" => ["dash"], "title" => "t", "xunit" => "cm", "ylab" => nothing))
        @test plot == Dict(:xlim => (nothing, 5), :linestyle => [:dash], :title => "t", :xunit => u"cm")
        @test Cropbox.decodeplot(nothing) == Dict{Symbol,Any}()
        # the kind of plot is a field of the request, and there is one backend
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("kind" => "scatter"))
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("backend" => "Makie"))
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("xlim" => [1]))
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("linestyle" => "wavy"))
    end

    @testset "operations" begin
        request = Dict(
            "config" => Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm")),
            "stop" => Dict("value" => 1, "unit" => "hr"), "target" => ["a", "b"],
        )
        p = Cropbox.simulate_payload(SWebAPI, request)
        @test p["status"] == "ok" && p["model"] == "SWebAPI" && p["contract_version"] == "0.2.0"
        @test [c["name"] for c in p["columns"]] == ["time", "a", "b"]
        @test [c["unit"] for c in p["columns"]] == ["hr", "m", "m"]
        @test length(p["rows"]) == 2 && p["rows"][end] == [1, 2, 2]
        @test p["summary"]["nrow"] == 2 && p["summary"]["elapsed_ms"] isa Integer
        direct = simulate(SWebAPI; config = :SWebAPI => :a => 2u"m", stop = 1u"hr", target = ["a", "b"])
        @test p["rows"] == [[Cropbox.deunitfy(x) for x in row] for row in eachrow(direct)]
        @test Cropbox.simulate_payload(SWebAPI, Dict("stop" => 2, "target" => "b", "nounit" => true))["columns"][2]["unit"] === nothing
        @test length(Cropbox.simulate_payload(SWebAPI, Dict("configs" => [Dict("SWebAPI.a" => 1), Dict("SWebAPI.a" => 2)], "stop" => 1, "target" => "b"))["rows"]) == 4
        # every default of the description can be sent back as a configuration
        index = Cropbox.ModelIndex(SWebAPI)
        defaults = Dict(q["path"] => q["default"] for q in describe(SWebAPI)["parameters"] if !isnothing(q["default"]["value"]))
        @test length(defaults) == 4 && Cropbox.simulate_payload(SWebAPI, Dict("config" => defaults, "stop" => 1, "target" => "b"); index)["rows"] == [[0, 1], [1, 1]]

        # nested systems: mixin and alias configuration paths, wildcards, `base` and `meta`
        index = Cropbox.ModelIndex(SWebPlant)
        nested = Cropbox.simulate_payload(SWebPlant, Dict("config" => Dict("SWebRate.k" => 3, "SWebLeaf.A" => Dict("value" => 4, "unit" => "cm^2")), "target" => ["total", "leaf.*"], "stop" => 1); index)
        columns = [c["name"] for c in nested["columns"]]
        @test issubset(["time", "total", "leaf.area", "leaf.doubled"], columns) && nested["rows"][end][findfirst(==("total"), columns)] == 24
        based = Cropbox.simulate_payload(SWebPlant, Dict("base" => "leaf", "target" => ["doubled", "A"], "stop" => 1); index)
        @test [c["name"] for c in based["columns"]] == ["time", "doubled", "A"] && based["rows"][end] == [1, 4, 2]
        @test_throws Cropbox.APIRequestError Cropbox.simulate_payload(SWebPlant, Dict("base" => "nope", "target" => "doubled"); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulate_payload(SWebPlant, Dict("base" => "leaf", "target" => "total"); index)
        runs = Cropbox.simulate_payload(SWebPlant, Dict("configs" => [Dict("SWebPlant.k" => 1), Dict("SWebPlant.k" => 2)], "meta" => ["SWebPlant", Dict("site" => "A")], "target" => "total", "stop" => 1); index)
        @test [c["name"] for c in runs["columns"]] == ["time", "total", "k", "site"]
        @test [r[2:end] for r in runs["rows"]] == [[4, 1, "A"], [4, 1, "A"], [8, 2, "A"], [8, 2, "A"]]
        @test_throws Cropbox.APIRequestError Cropbox.simulate_payload(SWebPlant, Dict("meta" => "SWebLeaf", "target" => "total"); index)
        # a `tabulate` parameter travels as an array of rows
        shares = merge(only(filter(q -> q["path"] == "SWebPlant.shares", describe(SWebPlant)["parameters"]))["default"], Dict("value" => [[0.1, 0.9], [0.2, 0.8]]))
        @test Cropbox.simulate_payload(SWebPlant, Dict("config" => Dict("SWebPlant.shares" => shares), "target" => "late_root", "stop" => 1); index)["rows"][end][2] == 0.8
        @test Cropbox.simulate_payload(SWebPlant, Dict("target" => "late_root", "stop" => 1); index)["rows"][end][2] == 0.5

        observed = Dict("type" => "DataFrame",
            "columns" => [Dict("name" => "time", "type" => "Float64", "unit" => "hr"), Dict("name" => "b", "type" => "Float64", "unit" => "m")],
            "rows" => [[0, 2], [1, 2], [2, 2]])
        e = Cropbox.evaluate_payload(SWebAPI, Dict("config" => Dict("SWebAPI" => Dict("a" => Dict("value" => 2, "unit" => "m"))), "observed" => observed, "target" => "b", "stop" => Dict("value" => 2, "unit" => "hr"), "metric" => "rmse"))
        @test e["status"] == "ok" && e["operation"] == "evaluate" && e["metric"] == "rmse" && e["target"] == "b"
        @test e["value"]["value"] == 0.0 && e["value"]["unit"] == "m" && e["summary"]["nobs"] == 3
        e2 = Cropbox.evaluate_payload(SWebAPI, Dict("config" => Dict("SWebAPI.a" => 1), "observed" => observed, "target" => "b", "stop" => 2))
        @test e2["value"]["value"] == 1.0
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("observed" => observed, "stop" => 2))
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("target" => "b", "stop" => 2))
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("observed" => "obs.csv", "target" => "b"))
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("observed" => observed, "target" => "b", "stop" => 2, "metric" => "nope"))
        # observations that match no output or lack the target are the request's error
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("observed" => merge(observed, Dict("rows" => [[100, 2]])), "target" => "b", "stop" => 2))
        @test_throws Cropbox.APIRequestError Cropbox.evaluate_payload(SWebAPI, Dict("observed" => observed, "target" => "a", "stop" => 2))

        @system SWebAPICalibration(Controller) begin
            a => 0 ~ preserve(parameter)
            b(a) => a ~ accumulate
        end
        calibration = Dict(
            "observed" => Dict("type" => "DataFrame", "columns" => [Dict("name" => "time", "type" => "Float64", "unit" => "hr"), Dict("name" => "b", "type" => "Float64")], "rows" => [[10, 200]]),
            "target" => "b", "stop" => 10,
            "parameters" => Dict("SWebAPICalibration.a" => [19.5, 20.5]),
            "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent"),
        )
        c = Cropbox.calibrate_payload(SWebAPICalibration, calibration)
        @test c["status"] == "ok" && c["operation"] == "calibrate" && c["summary"]["nparameters"] == 1
        @test 19.5 <= c["config"]["SWebAPICalibration"]["a"]["value"] <= 20.5
        @test_throws Cropbox.APIRequestError Cropbox.calibrate_payload(SWebAPICalibration, delete!(copy(calibration), "parameters"))
        @test_throws Cropbox.APIRequestError Cropbox.calibrate_payload(SWebAPICalibration, merge(calibration, Dict("parameters" => Dict("SWebAPICalibration.zzz" => [0, 1]))); index = Cropbox.ModelIndex(SWebAPICalibration))
        for option in ("SaveTrace", "SaveFitnessTraceToCsv", "SaveParameters")
            @test_throws Cropbox.APIRequestError Cropbox.calibrate_payload(SWebAPICalibration, merge(calibration, Dict("optim" => Dict(option => true))))
        end
        # bounds in any unit of a parameter by any of its names, for a system that `calibrate` cannot look up
        growth = Dict(
            "observed" => Dict("type" => "CSV", "content" => "time (hr),h (cm)\n10,200\n"), "target" => "h", "stop" => 10,
            "parameters" => Dict("SWebGrowth.rate" => Dict("lower" => 0.195, "upper" => 0.205, "unit" => "m/hr")),
            # any option of the optimizer goes through, except the ones that write files where the service runs
            "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent", "MaxNumStepsWithoutFuncEvals" => 50),
        )
        r = Cropbox.calibrate_payload(WebAPITestModels.SWebGrowth, growth; index = Cropbox.ModelIndex(WebAPITestModels.SWebGrowth))["config"]["SWebGrowth"]["r"]
        @test 19.5 <= r["value"] <= 20.5 && r["unit"] == "cm*hr^-1"

        v = Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "stop" => Dict("value" => 2, "unit" => "hr"), "kind" => "scatterline", "plot" => Dict("title" => "b over time")))
        @test v["status"] == "ok" && v["operation"] == "visualize" && v["format"] == "svg" && v["content_type"] == "image/svg+xml"
        @test startswith(strip(v["body"]), "<?xml") || startswith(strip(v["body"]), "<svg")
        @test occursin("<svg", v["body"])
        stepped = Cropbox.visualize_payload(SWebAPI, Dict("x" => "time", "y" => ["b"], "stop" => 2, "xstep" => Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 3, "step" => 1, "unit" => "m")))
        @test occursin("<svg", stepped["body"])
        from_table = Cropbox.visualize_payload(SWebAPI, Dict("data" => Dict("type" => "DataFrame", "columns" => p["columns"], "rows" => p["rows"]), "x" => "time", "y" => "b", "kind" => "line"))
        @test occursin("<svg", from_table["body"])
        # the dashboard plots the simulated table back with `null` cells and partial limits
        gapped = Dict("type" => "DataFrame", "columns" => [Dict("name" => "time", "type" => "Int64", "unit" => "hr"), Dict("name" => "b", "type" => "Float64", "unit" => "m")], "rows" => [[0, 1.0], [1, nothing], [2, 3.0]])
        from_gapped = Cropbox.visualize_payload(SWebAPI, Dict("data" => gapped, "x" => "time", "y" => ["b"], "kind" => "scatter", "plot" => Dict("xlim" => [nothing, 5], "ylim" => [0, nothing])))
        @test occursin("<svg", from_gapped["body"])
        # a `data` table is plotted by its own column names, whatever the model declares
        other = Dict("type" => "DataFrame", "columns" => [Dict("name" => "day", "type" => "Float64", "unit" => "d"), Dict("name" => "height", "type" => "Float64", "unit" => "cm")], "rows" => [[0, 1], [1, 3]])
        @test occursin("<svg", Cropbox.visualize_payload(SWebAPI, Dict("data" => other, "x" => "day", "y" => "height"); index = Cropbox.ModelIndex(SWebAPI))["body"])
        # the simulated table goes back as it came
        @test occursin("<svg", Cropbox.visualize_payload(SWebAPI, Dict("data" => JSON.parse(JSON.json(p)), "y" => ["a", "b"], "plot" => Dict("linestyle" => ["solid", "dash"])))["body"])
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("data" => p, "y" => ["a", "b"], "plot" => Dict("linestyle" => ["solid"])))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => Dict("len" => "b")))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "kind" => "pie"))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "target" => "b"))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("data" => other, "x" => "day", "y" => "b"))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("stop" => 2))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "backend" => "UnicodePlots"))
        # what the plot rejects in a finished table is the request's error: one label for two series, units that share no axis
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => ["a", "b"], "stop" => 1, "plot" => Dict("names" => ["one"])))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("data" => other, "x" => "day", "y" => ["day", "height"]))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => []))
        # the constructor options of the service reach every operation that runs the model
        @test Cropbox.simulate_payload(SWebExternal, Dict("target" => "x", "stop" => 1); options = (a = 3,))["rows"][end][2] == 3
        @test occursin("<svg", Cropbox.visualize_payload(SWebExternal, Dict("y" => "x", "stop" => 1); options = (a = 3,))["body"])

        t = Cropbox.simulate_payload(SWebTable, Dict("config" => Dict("SWebTable.weather" => weather_table), "stop" => Dict("value" => 2, "unit" => "d"), "target" => "T"))
        @test [r[2] for r in t["rows"]] == [10, 12, 14] && t["columns"][2]["unit"] == "°C"
    end

    @testset "widgets" begin
        w = Cropbox.widgetpayload(SWebAPI)
        @test w["title"] == "SWebAPI Dashboard" && w["model"]["name"] == "SWebAPI"
        C = Dict(c["path"] => c for c in w["controls"])
        @test Set(keys(C)) == Set(["SWebAPI.a", "SWebAPI.c", "SWebAPI.f", "SWebAPI.n", "SWebAPI.d", "Clock.step"])
        @test C["SWebAPI.a"]["kind"] == "number" && C["SWebAPI.a"]["unit"] == "m" && C["SWebAPI.a"]["default"] == 1 && C["SWebAPI.a"]["value_type"] == "Float64" && C["SWebAPI.a"]["step"] == 0.1
        @test C["SWebAPI.a"]["label"] == "a" && C["SWebAPI.a"]["alias"] == "length" && C["SWebAPI.a"]["declared"] == "SWebAPI.a"
        @test C["SWebAPI.c"]["kind"] == "number" && C["SWebAPI.c"]["unit"] === nothing
        @test C["SWebAPI.f"]["kind"] == "checkbox" && C["SWebAPI.f"]["default"] === true
        @test C["SWebAPI.n"]["kind"] == "number" && C["SWebAPI.n"]["step"] == 1 && C["SWebAPI.n"]["value_type"] == "Int"
        @test C["SWebAPI.d"]["kind"] == "number" && C["SWebAPI.d"]["default"] === nothing && C["SWebAPI.d"]["value_type"] == "Float64"
        @test C["Clock.step"]["source"] == "runtime" && C["Clock.step"]["default"] == 1 && C["Clock.step"]["unit"] == "hr"
        @test first(w["outputs"])["target"] == "time" && first(w["outputs"])["unit"] == "hr"
        @test Set(v["target"] for v in w["outputs"]) == Set(["time", "b", "g"])
        @test w["simulation"] == Dict("stop" => Dict("value" => 5, "unit" => "hr"), "snap" => nothing)
        @test Cropbox.widgetpayload(SWebTable)["simulation"]["stop"] == Dict("value" => 5, "unit" => "d")
        # nothing a dashboard does not read
        @test Set(keys(w)) == Set(["title", "model", "controls", "outputs", "tables", "simulation", "panels"])
        @test only(w["panels"]) == Dict("title" => "Panel 1", "x" => "time", "y" => ["b"], "kind" => "line")
        @test !haskey(w, "sweeps")

        ui = Dict("title" => "Custom", "outputs" => ["g"], "panels" => [Dict("title" => "Flag", "x" => "time", "y" => ["g"])], "sweeps" => [Dict("path" => "SWebAPI.a")])
        # a dashboard starts from the `stop` and `snap` among the request defaults of the service
        defaults = Dict("stop" => 3u"hr", "snap" => Dict("value" => 1, "unit" => "hr"))
        w2 = Cropbox.widgetpayload(SWebAPI; config = :SWebAPI => :a => 4u"m", ui, defaults)
        @test w2["title"] == "Custom" && [v["target"] for v in w2["outputs"]] == ["time", "g"]
        @test only(w2["panels"])["y"] == ["g"] && w2["sweeps"] == ui["sweeps"]
        @test w2["simulation"] == Dict("stop" => Dict("value" => 3, "type" => "Int64", "unit" => "hr"), "snap" => Dict("value" => 1, "unit" => "hr"))
        # a condition is shown by its path; a Julia function stays with the service
        @test Cropbox.widgetpayload(SWebAPI; defaults = Dict("stop" => :g, "snap" => identity))["simulation"] == Dict("stop" => "g", "snap" => nothing)
        @test_throws Cropbox.APIRequestError Cropbox.widgetpayload(SWebAPI; ui = Dict("stop" => 3))
        @test only(filter(c -> c["path"] == "SWebAPI.a", w2["controls"]))["default"] == 4

        # requested outputs resolve by target, name or alias and may name parameters
        @test [v["target"] for v in Cropbox.widgetpayload(SWebAPI; ui = Dict("outputs" => ["b", "length"]))["outputs"]] == ["time", "b", "a"]
        @test [v["target"] for v in Cropbox.widgetpayload(SWebPlant; ui = Dict("outputs" => ["doubled", "total"]))["outputs"]] == ["time", "leaf.doubled", "total"]
        clockstep(S; kw...) = only(filter(c -> c["path"] == "Clock.step", Cropbox.widgetpayload(S; kw...)["controls"]))
        @test clockstep(SWebAPI; config = :Clock => :step => 2u"hr")["default"] == 2
        @test clockstep(SWebTable; config = :Clock => :step => 2u"d")["default"] == 2 && clockstep(SWebTable)["default"] == 1

        wt = Cropbox.widgetpayload(SWebTable)
        weather = only(filter(c -> c["name"] == "weather", wt["controls"]))
        @test weather["role"] == "table" && weather["kind"] == "file" && weather["accept"] == ".csv,text/csv" && weather["value_type"] == "TableInput"
        @test only(weather["columns"])["column"] == "tavg"
        @test any(v -> v["name"] == "T", wt["outputs"])
        step = only(filter(c -> c["path"] == "Clock.step", wt["controls"]))
        @test step["unit"] == "d" && step["system"] == "DailyClock"
        columns = [Dict("name" => "index", "type" => "Float64", "unit" => "d"), Dict("name" => "tavg", "type" => "Float64", "unit" => "°C")]
        wt2 = Cropbox.widgetpayload(SWebTable; ui = Dict("table_inputs" => [Dict("path" => "SWebTable.weather", "label" => "Daily weather", "default_filename" => "weather.csv", "columns" => columns)]))
        configured = only(filter(c -> c["name"] == "weather", wt2["controls"]))
        @test configured["label"] == "Daily weather" && configured["default_filename"] == "weather.csv" && configured["columns"] == columns
        @test_throws ErrorException Cropbox.widgetpayload(SWebTable; ui = Dict("table_inputs" => [Dict("path" => "SWebTable.nope")]))
        # panels plot from the outputs, so their variables (parameters too) are among them; a name the model lacks is an error
        wp = Cropbox.widgetpayload(SWebAPI; ui = Dict("outputs" => ["g"], "panels" => [Dict("x" => "length", "y" => "b")]))
        @test [v["target"] for v in wp["outputs"]] == ["time", "g", "a", "b"] && only(wp["panels"]) == Dict("x" => "a", "y" => ["b"])
        @test_throws ErrorException Cropbox.widgetpayload(SWebAPI; ui = Dict("outputs" => ["nope"]))
        @test_throws ErrorException Cropbox.widgetpayload(SWebAPI; ui = Dict("panels" => [Dict("y" => ["nope"])]))
        # a zoned default keeps the name of its zone for the control
        @system SWebDated(Controller) begin
            t0 => ZonedDateTime(2024, 1, 2, tz"America/New_York") ~ preserve::datetime(parameter)
        end
        dated = only(filter(c -> c["name"] == "t0", Cropbox.widgetpayload(SWebDated)["controls"]))
        @test dated["kind"] == "text" && dated["value_type"] == "ZonedDateTime" && dated["timezone"] == "America/New_York" && dated["default"] == "2024-01-02T00:00:00-05:00"
    end

    @testset "service" begin
        defaults = Dict(
            "stop" => Dict("value" => 2, "unit" => "hr"),
            "snap" => Dict("value" => 1, "unit" => "hr"),
            "config" => Dict("SWebAPI.a" => Dict("value" => 3, "unit" => "m"), "SWebAPI.c" => 7),
        )
        s = Cropbox.Service(SWebAPI; request_defaults = defaults, options = (x = 1,))
        post(path, payload) = begin
            status, type, body = Cropbox.respond(s, "POST", path, JSON.json(payload))
            status, type, JSON.parse(body)
        end
        getroute(path) = Cropbox.respond(s, "GET", path)

        status, type, body = getroute("/api/model")
        @test status == 200 && type == "application/json; charset=utf-8" && JSON.parse(body)["model"]["name"] == "SWebAPI"
        board = JSON.parse(getroute("/api/dashboard")[3])
        @test board["title"] == "SWebAPI Dashboard" && board["simulation"] == Dict("stop" => defaults["stop"], "snap" => defaults["snap"])
        schema = JSON.parse(getroute("/api/schema")[3])
        @test schema["contract_version"] == "0.2.0" && any(r -> r["path"] == "/api/simulate" && r["method"] == "POST", schema["routes"])
        @test schema["definitions"]["SimulationRequest"]["allOf"] == [Dict("\$ref" => "#/definitions/RunRequest")] && !occursin("#/components/", getroute("/api/schema")[3])
        # the document lists the fields that each operation accepts and the dashboard metadata that is served
        properties(name) = begin
            d = schema["definitions"][name]
            P = Set{String}(keys(get(d, "properties", Dict())))
            for r in get(d, "allOf", [])
                union!(P, properties(String(last(split(r["\$ref"], "/")))))
            end
            P
        end
        for (op, name) in pairs((simulate = "SimulationRequest", evaluate = "EvaluationRequest", calibrate = "CalibrationRequest", visualize = "VisualizationRequest"))
            @test properties(name) == Set(Cropbox.REQUEST_KEYS[op])
        end
        @test issubset(keys(board), properties("WidgetPayload"))
        openapi = JSON.parse(getroute("/api/openapi")[3])
        @test openapi["info"]["version"] == "0.2.0" && Set(keys(openapi["paths"])) == Set(["/api/model", "/api/dashboard", "/api/schema", "/api/openapi", "/api/docs", "/api/simulate", "/api/visualize", "/api/evaluate", "/api/calibrate"])
        @test getroute("/api/docs")[1] == 200 && occursin("swagger-ui", getroute("/api/docs")[3]) && getroute("/docs")[1] == 200
        @test getroute("/")[2] == "text/html; charset=utf-8" && occursin("<html", getroute("/dashboard")[3])
        @test getroute("/api/model?x=1")[1] == 200
        # the default configuration is part of what the service describes
        @test only(filter(q -> q["path"] == "SWebAPI.a", JSON.parse(getroute("/api/model")[3])["parameters"]))["default"]["value"] == 3

        status, _, body = getroute("/missing")
        @test status == 404 && JSON.parse(body)["error"]["code"] == "not_found" && JSON.parse(body)["status"] == "error"
        @test getroute("/api/simulate")[1] == 405 && JSON.parse(getroute("/api/simulate")[3])["error"]["code"] == "method_not_allowed"
        @test Cropbox.respond(s, "POST", "/api/model", "{}")[1] == 405
        status, _, body = Cropbox.respond(s, "POST", "/api/simulate", "{not json")
        @test status == 400 && JSON.parse(body)["error"]["category"] == "syntax"
        status, _, body = Cropbox.respond(s, "POST", "/api/simulate", "[1, 2]")
        @test status == 400

        status, _, body = post("/api/simulate", Dict("target" => ["a", "b", "c"]))
        @test status == 200 && length(body["rows"]) == 3 && body["rows"][1][2] == 3 && body["rows"][1][4] == 7
        status, _, body = post("/api/simulate", Dict("target" => ["a", "c"], "config" => Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm")), "stop" => 1))
        @test status == 200 && length(body["rows"]) == 2 && body["rows"][1][2] == 2 && body["rows"][1][3] == 7
        status, _, body = post("/api/simulate", Dict("target" => "a", "config" => Dict("SWebAPI.a" => "2.5")))
        @test status == 200 && body["rows"][1][2] == 2.5
        status, _, body = post("/api/simulate", Dict("target" => "a", "config" => Dict("SWebAPI.zzz" => 1)))
        @test status == 422 && body["error"]["category"] == "validation" && occursin("zzz", body["error"]["message"])
        status, _, body = post("/api/simulate", Dict("target" => "zzz"))
        @test status == 422 && occursin("zzz", body["error"]["message"])
        status, _, body = post("/api/simulate", Dict("target" => "a", "config" => [Dict("path" => "SWebAPI.a", "value" => 1)]))
        @test status == 422
        # what fails while the model runs is an execution error, reported by its cause without stack traces
        broken = Cropbox.Service(SWebBroken; dashboard = :none)
        for (route, request) in (("/api/simulate", Dict("target" => "x")), ("/api/visualize", Dict("y" => "x")),
                                 ("/api/evaluate", Dict("target" => "x", "observed" => Dict("type" => "CSV", "content" => "time (hr),x\n0,1\n"))))
            status, _, body = Cropbox.respond(broken, "POST", route, JSON.json(request))
            failure = JSON.parse(body)["error"]
            @test status == 500 && failure["category"] == "execution" && failure["code"] == "execution_failed"
            @test occursin("broken", failure["message"]) && !occursin("Stacktrace", failure["message"]) && !occursin("TaskFailedException", failure["message"])
        end
        # values the model cannot take are the client's error, not an execution failure
        for bad in (Dict("seed" => "abc"), Dict("config" => Dict("SWebAPI.n" => Dict("value" => 1.5, "type" => "Int"))),
                    Dict("config" => Dict("SWebAPI.a" => Dict("value" => 1, "unit" => "nounit"))), Dict("meta" => "Nope"), Dict("base" => "nope"),
                    Dict("config" => Dict("SWebAPI.a" => [1, 2])), Dict("config" => Dict("SWebAPI.a" => Dict("value" => 1, "unit" => "kg"))),
                    Dict("stop" => Dict("value" => 1, "unit" => "kg")), Dict("config" => Dict("SWebAPI.n" => 1.5)),
                    Dict("config" => Dict("SWebAPI.n" => nothing)), Dict("config" => Dict("SWebAPI.f" => 2)))
            status, _, body = post("/api/simulate", merge(Dict{String,Any}("target" => "a"), bad))
            @test status == 422 && body["error"]["category"] == "validation"
        end
        status, _, body = post("/api/visualize", Dict("y" => "b", "xstep" => Dict("path" => "SWebAPI.zzz", "values" => [1, 2])))
        @test status == 422 && occursin("zzz", body["error"]["message"])
        # fields an operation does not have are rejected, not ignored, and defaults only apply where they are fields
        for (route, bad) in (("/api/simulate", Dict("target" => "a", "config_entries" => [])), ("/api/simulate", Dict("target" => "a", "snap" => 5)),
                             ("/api/simulate", Dict("target" => "a", "options" => Dict("x" => 2))), ("/api/visualize", Dict("y" => "b", "backend" => "Makie")),
                             ("/api/visualize", Dict("y" => "b", "plot" => Dict("kind" => "line"))), ("/api/evaluate", Dict("target" => "b", "snap" => true)))
            status, _, body = post(route, bad)
            @test status == 422 && body["error"]["category"] == "validation"
        end
        @test_throws Cropbox.APIRequestError Cropbox.Service(SWebAPI; request_defaults = Dict("stopp" => 1))
        @test_throws Cropbox.APIRequestError Cropbox.Service(SWebAPI; ui = Dict("external_sources" => []))
        # an empty `configs` and an explicit `time` index keep the defaults
        status, _, body = post("/api/simulate", Dict("target" => "a", "configs" => [], "index" => "time"))
        @test status == 200 && [c["name"] for c in body["columns"]] == ["time", "a"] && body["rows"][1] == [0, 3]

        observed = Dict("type" => "CSV", "content" => "time (hr),b (m)\n0,3\n1,3\n2,3\n")
        status, _, body = post("/api/evaluate", Dict("observed" => observed, "target" => "b"))
        @test status == 200 && body["value"]["value"] == 0.0 && body["summary"]["nobs"] == 3
        status, _, body = post("/api/evaluate", Dict("observed" => observed, "target" => "b", "index" => "time"))
        @test status == 200 && body["value"]["value"] == 0.0
        # observations the outputs do not match, or that lack the target, are the request's error
        status, _, body = post("/api/evaluate", Dict("observed" => Dict("type" => "CSV", "content" => "time (hr),b (m)\n100,3\n"), "target" => "b"))
        @test status == 422 && body["error"]["category"] == "validation" && occursin("no matching", body["error"]["message"])
        @test post("/api/evaluate", Dict("observed" => observed, "target" => "a"))[1] == 422
        # so is a table that would lose values
        table = Dict("type" => "DataFrame", "columns" => [Dict("name" => "a"), Dict("name" => "b")], "rows" => [[0, 1, 999], [1, 2, 888]])
        @test post("/api/visualize", Dict("data" => table, "x" => "a", "y" => "b"))[1] == 422
        status, _, body = post("/api/visualize", Dict("y" => "b"))
        @test status == 200 && body["format"] == "svg"

        ts = Cropbox.Service(SWebTable; dashboard = :none)
        @test Cropbox.respond(ts, "GET", "/")[1] == 404 && Cropbox.respond(ts, "GET", "/dashboard")[1] == 404
        # a table only comes from the data a client sends, by whatever name it addresses the parameter
        for path in ("SWebTable.weather", "System.weather", "Controller.weather")
            status, _, body = Cropbox.respond(ts, "POST", "/api/simulate", JSON.json(Dict("config" => Dict(path => "/etc/passwd"), "target" => "T", "stop" => 1)))
            @test status == 422 && JSON.parse(body)["error"]["category"] == "validation"
        end
        status, _, body = Cropbox.respond(ts, "POST", "/api/simulate", JSON.json(Dict("config" => Dict("SWebTable.weather" => weather_table), "target" => "T", "stop" => Dict("value" => 2, "unit" => "d"))))
        @test status == 200 && [r[2] for r in JSON.parse(body)["rows"]] == [10, 12, 14]

        custom = Cropbox.Service(SWebAPI; dashboard = "/ui")
        @test Cropbox.respond(custom, "GET", "/ui")[1] == 200 && Cropbox.respond(custom, "GET", "/")[1] == 404

        # a client value replaces the server's whichever name of the parameter either used
        plant = Cropbox.Service(SWebPlant; config = (:SWebPlant => :k => 2, :SWebLeaf => :area => 1u"cm^2"), dashboard = :none)
        total(config) = JSON.parse(Cropbox.respond(plant, "POST", "/api/simulate", JSON.json(Dict("config" => config, "target" => "total", "stop" => 1)))[3])["rows"][end][2]
        @test total(Dict()) == 4 && total(Dict("SWebRate.rate" => 5)) == 10 && total(Dict("System.k" => 5, "SWebLeaf.A" => Dict("value" => 2, "unit" => "cm^2"))) == 20
        @test Cropbox.dashboardpaths(:static) == ["/", "/dashboard"] && Cropbox.dashboardpaths("/ui") == ["/ui"]
        @test isempty(Cropbox.dashboardpaths(false)) && isempty(Cropbox.dashboardpaths(:none)) && isempty(Cropbox.dashboardpaths(nothing))
        @test_throws ErrorException Cropbox.dashboardpaths(:bogus)
        @test_throws ErrorException Cropbox.dashboardpaths("ui")

        # a default configuration replaces the base one, and a client's the default, whichever name of a parameter each used
        aliased = Cropbox.Service(SWebAPI; config = :SWebAPI => :a => 3, request_defaults = Dict("config" => Dict("SWebAPI.length" => 4)), dashboard = :none)
        served(config) = JSON.parse(Cropbox.respond(aliased, "POST", "/api/simulate", JSON.json(Dict("config" => config, "target" => "a")))[3])["rows"][1][2]
        @test served(Dict()) == 4 && served(Dict("SWebAPI.length" => 5)) == 5 && served(Dict("Controller.a" => 6)) == 6
        @test only(filter(q -> q["path"] == "SWebAPI.a", JSON.parse(Cropbox.respond(aliased, "GET", "/api/model")[3])["parameters"]))["default"]["value"] == 4

        # so does a server value set under the module-qualified name of the system, which Cropbox reads first
        own = "$(first(names(SWebAPI))).a"
        for qualified in (Cropbox.Service(SWebAPI; config = own => 3, dashboard = :none),
                          Cropbox.Service(SWebAPI; request_defaults = Dict("config" => Dict(own => 3)), dashboard = :none))
            value(config) = JSON.parse(Cropbox.respond(qualified, "POST", "/api/simulate", JSON.json(Dict("config" => config, "target" => "a")))[3])["rows"][1][2]
            @test value(Dict()) == 3 && value(Dict("SWebAPI.a" => 4)) == 4 && value(Dict("SWebAPI.length" => 5)) == 5 && value(Dict(own => 6)) == 6
        end
        # a namesake from another module keeps its own value, and the shared name sets both
        twins = WebAPITestModels.SWebTwins
        twinA = "$(first(names(WebAPITestModels.NamesakeA.SWebTwin))).a"
        paired = Cropbox.Service(twins; config = twinA => 5, dashboard = :none)
        pair(config) = JSON.parse(Cropbox.respond(paired, "POST", "/api/simulate", JSON.json(Dict("config" => config, "target" => ["x.a", "y.a"])))[3])["rows"][1][2:3]
        @test pair(Dict()) == [5, 2] && pair(Dict("SWebTwin.a" => 7)) == [7, 7] && pair(Dict(twinA => 8)) == [8, 2]
        # so does a sweep over one of them, by its qualified path, and over both by the shared name
        twinB = "$(first(names(WebAPITestModels.NamesakeB.SWebTwin))).a"
        both = Cropbox.Service(twins; config = (twinA => 5, twinB => 7), dashboard = :none)
        readA(c) = Cropbox.option(c, names(WebAPITestModels.NamesakeA.SWebTwin), :a)
        readB(c) = Cropbox.option(c, names(WebAPITestModels.NamesakeB.SWebTwin), :a)
        swept(path) = Cropbox.simulationkwargs(Dict{String,Any}("xstep" => Dict("path" => path, "values" => [3, 4]));
            both.config, index = both.index, fields = Cropbox.REQUEST_KEYS.visualize)[:configs]
        @test [(readA(c), readB(c)) for c in swept(twinA)] == [(3, 7), (4, 7)]
        @test [(readA(c), readB(c)) for c in swept("SWebTwin.a")] == [(3, 3), (4, 4)]
        # and a calibration of one of them by its qualified path
        bounded = Cropbox.calibrationrange(twinA => [0, 10], both.index)
        @test first(bounded) == Symbol(first(names(WebAPITestModels.NamesakeA.SWebTwin))) && last(last(bounded)) == [0, 10]
        @test_throws Cropbox.APIRequestError Cropbox.calibrationrange("SWebTwin.a" => [0, 10], both.index)
        # its answer, under the qualified name of the system, goes back as a configuration as it is
        status, _, body = Cropbox.respond(both, "POST", "/api/calibrate", JSON.json(Dict(
            "observed" => Dict("type" => "CSV", "content" => "time (hr),x.a\n0,3\n"), "target" => "x.a", "stop" => 1,
            "parameters" => Dict(twinA => [0, 10]), "optim" => Dict("MaxSteps" => 500))))
        answer = JSON.parse(body)["config"]
        @test status == 200 && only(keys(answer)) == chop(twinA; tail = 2)
        status, _, body = Cropbox.respond(both, "POST", "/api/simulate", JSON.json(Dict("config" => answer, "target" => ["x.a", "y.a"])))
        @test status == 200 && isapprox(JSON.parse(body)["rows"][1][2], 3; atol = 0.05) && JSON.parse(body)["rows"][1][3] == 7
        # a value for one system leaves a base value under a name it shares with another to that one, whichever name the
        # client uses; the name both answer to sets both
        leafA = string(first(names(WebAPITestModels.SharedA.Shared.SWebLeaf)))
        leaves = Cropbox.Service(WebAPITestModels.SWebLeaves; config = "Shared.SWebLeaf.a" => 3, dashboard = :none)
        leafpair(config) = JSON.parse(Cropbox.respond(leaves, "POST", "/api/simulate", JSON.json(Dict("config" => config, "target" => ["x.a", "y.a"])))[3])["rows"][1][2:3]
        @test leafpair(Dict()) == [3, 3] && leafpair(Dict("$leafA.a" => 5)) == [5, 3] && leafpair(Dict("SharedA.Shared.SWebLeaf.a" => 5)) == [5, 3]
        @test leafpair(Dict(leafA => Dict("a" => 5))) == [5, 3] && leafpair(Dict("Shared.SWebLeaf.a" => 5)) == [5, 5] && leafpair(Dict("SWebLeaf.a" => 6)) == [6, 6]
        # a calibration of a parameter named like a key of a range answers a configuration that goes back as it is
        status, _, body = Cropbox.respond(leaves, "POST", "/api/calibrate", JSON.json(Dict(
            "observed" => Dict("type" => "CSV", "content" => "time (hr),x.lower\n0,3\n"), "target" => "x.lower", "stop" => 1,
            "parameters" => Dict("$leafA.lower" => [0, 10]), "optim" => Dict("MaxSteps" => 500))))
        answer = JSON.parse(body)["config"]
        @test status == 200 && only(keys(answer)) == leafA && only(keys(answer[leafA])) == "lower"
        status, _, body = Cropbox.respond(leaves, "POST", "/api/simulate", JSON.json(Dict("config" => answer, "target" => ["x.lower", "y.lower"])))
        @test status == 200 && isapprox(JSON.parse(body)["rows"][1][2], 3; atol = 0.05) && JSON.parse(body)["rows"][1][3] == 1
        # a calibrated parameter that the base holds under a spelling read first is calibrated, not left at the base
        # value, in a run of several configurations as in one; the answer goes by the system's own name
        shadow = Cropbox.Service(SWebAPI; config = own => 3, dashboard = :none)
        for extra in (Dict(), Dict("configs" => [Dict()]), Dict("configs" => [Dict("SWebAPI.c" => 1)]))
            status, _, body = Cropbox.respond(shadow, "POST", "/api/calibrate", JSON.json(merge(Dict(
                "observed" => Dict("type" => "CSV", "content" => "time (hr),a (m)\n0,7\n"), "target" => "a", "stop" => 1,
                "parameters" => Dict("SWebAPI.a" => [0, 10]), "optim" => Dict("MaxSteps" => 500)), extra)))
            calibrated = JSON.parse(body)["config"]
            @test status == 200 && only(keys(calibrated)) == "SWebAPI" && isapprox(calibrated["SWebAPI"]["a"]["value"], 7; atol = 0.05)
        end
        # `meta` records the values in effect, a client's through an alias of a mixin over the server's own name
        metered = Cropbox.Service(SWebPlant; config = :SWebPlant => :k => 3, dashboard = :none)
        kw = Cropbox.simulationkwargs(Dict{String,Any}("configs" => [Dict("SWebRate.rate" => 4), Dict("SWebRate.rate" => 5)], "meta" => "SWebPlant");
            metered.config, index = metered.index)
        @test [c[:SWebPlant][:k] for c in kw[:configs]] == [4, 5] && kw[:meta] == :SWebPlant

        # the constructor options of the service reach the operations that run the model
        external = Cropbox.Service(SWebExternal; options = (a = 3,), dashboard = :none)
        @test JSON.parse(Cropbox.respond(external, "POST", "/api/simulate", JSON.json(Dict("target" => "x", "stop" => 1)))[3])["rows"][end][2] == 3
        @test Cropbox.respond(external, "POST", "/api/visualize", JSON.json(Dict("y" => "x", "stop" => 1)))[1] == 200
    end

    @testset "guide" begin
        # the model of the web service guide, and what the guide says its requests return
        @system SWebGuide(Controller) begin
            "Height gained per hour."
            r: growth_rate => 0.5 ~ preserve(parameter, u"cm/hr")
            "Plant height."
            h(r): height ~ accumulate(u"cm")
        end
        model = describe(SWebGuide)
        parameter = only(model["parameters"])
        @test parameter["path"] == "SWebGuide.r" && parameter["alias"] == "growth_rate" && parameter["unit"] == "cm*hr^-1"
        @test [v["target"] for v in model["variables"]] == ["h"]
        service = Cropbox.Service(SWebGuide; config = :SWebGuide => :r => 2u"cm/hr", request_defaults = Dict("stop" => Dict("value" => 3, "unit" => "d")))
        request = Dict("config" => Dict("SWebGuide.growth_rate" => Dict("value" => 10, "unit" => "mm/hr")), "stop" => Dict("value" => 3, "unit" => "hr"), "target" => ["height"])
        status, _, body = Cropbox.respond(service, "POST", "/api/simulate", JSON.json(request))
        table = JSON.parse(body)
        @test status == 200 && table["columns"] == [Dict("name" => "time", "type" => "Float64", "unit" => "hr"), Dict("name" => "height", "type" => "Float64", "unit" => "cm")]
        @test table["rows"] == [[0, 0], [1, 1], [2, 2], [3, 3]] && table["summary"]["nrow"] == 4
        # the table goes back as `data`, with no second simulation
        status, _, body = Cropbox.respond(service, "POST", "/api/visualize", JSON.json(Dict("data" => table, "x" => "time", "y" => "height", "kind" => "line")))
        @test status == 200 && occursin("<svg", JSON.parse(body)["body"])
        # the dashboard starts from the request defaults
        @test JSON.parse(Cropbox.respond(service, "GET", "/api/dashboard")[3])["simulation"]["stop"] == Dict("value" => 3, "unit" => "d")
    end

    @testset "http" begin
        server = serve(SWebAPI; host = "127.0.0.1", port = 0, async = true, request_defaults = Dict("stop" => 1))
        try
            url = "http://127.0.0.1:$(Cropbox.HTTP.port(server))"
            model = JSON.parse(String(Cropbox.HTTP.get("$url/api/model").body))
            @test model["model"]["name"] == "SWebAPI"
            response = Cropbox.HTTP.post("$url/api/simulate", ["Content-Type" => "application/json"], JSON.json(Dict("target" => ["a", "b"])))
            @test response.status == 200
            body = JSON.parse(String(response.body))
            @test [c["name"] for c in body["columns"]] == ["time", "a", "b"] && length(body["rows"]) == 2
            html = Cropbox.HTTP.get("$url/dashboard")
            @test html.status == 200 && occursin("<html", String(html.body))
            missing_route = Cropbox.HTTP.get("$url/nope"; status_exception = false)
            @test missing_route.status == 404
            bad = Cropbox.HTTP.post("$url/api/simulate", ["Content-Type" => "application/json"], "{"; status_exception = false)
            @test bad.status == 400
        finally
            close(server)
        end
        api_only = dashboard(SWebAPI; host = "127.0.0.1", port = 0, async = true, frontend = :none)
        try
            url = "http://127.0.0.1:$(Cropbox.HTTP.port(api_only))"
            @test Cropbox.HTTP.get("$url/dashboard"; status_exception = false).status == 404
            @test Cropbox.HTTP.get("$url/api/openapi").status == 200
        finally
            close(api_only)
        end
    end
end
