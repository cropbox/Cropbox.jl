using DataFrames
using Dates
using JSON
using TimeZones

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

    @system SWebPlant(SWebRate, Controller) begin
        leaf(context) ~ ::SWebLeaf
        total(x=leaf.doubled, k) => k * x ~ track(u"cm^2")
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
        index = Cropbox.ModelIndex(d)
        @test issubset(["length", "b", "time", "*"], index.paths) && index.systems == Set(["SWebAPI"])
        @test index.types["SWebAPI.a"] == index.types["SWebAPI.length"] == ("Float64", "parameter")

        configured = describe(SWebAPI; config = :SWebAPI => :a => 300u"cm")
        @test only(filter(p -> p["name"] == "a", configured["parameters"]))["default"]["value"] == 3

        vars = Cropbox.variables(SWebAPI)
        @test all(v -> v.info isa Cropbox.VarInfo, vars)
        @test only(filter(v -> v.name == :a, vars)).config == "SWebAPI.a"

        t = describe(SWebTable)
        table = only(t["tables"])
        @test table["path"] == "SWebTable.weather" && table["role"] == "table" && table["state"] == "provide"
        @test table["index"] == "index"
        @test only(table["columns"]) == Dict("variable" => "T", "name" => "T", "column" => "tavg", "unit" => "°C")
        @test only(filter(p -> p["name"] == "weather", t["parameters"]))["default"] === nothing
        @test Cropbox.ModelIndex(t).types["SWebTable.weather"] == (nothing, "table")

        n = describe(SWebPlant)
        @test [(s["name"], s["path"], s["root"]) for s in n["systems"]] == [("SWebPlant", "", true), ("SWebLeaf", "leaf", false)]
        P = Dict(p["path"] => p for p in n["parameters"])
        @test P["SWebPlant.k"]["declared"] == "SWebRate.k" && P["SWebPlant.k"]["alias"] == "rate" && P["SWebPlant.k"]["target"] == "k"
        @test P["SWebLeaf.area"]["target"] == "leaf.area" && P["SWebLeaf.area"]["default"] == Dict("value" => 2, "type" => "Float64", "unit" => "cm^2")
        @test Set(v["target"] for v in n["variables"] if v["role"] == "output") == Set(["total", "leaf.doubled"])
        index = Cropbox.ModelIndex(n)
        @test issubset(["SWebPlant.k", "SWebRate.k", "SWebPlant.rate", "SWebRate.rate", "SWebLeaf.area", "SWebLeaf.A"], keys(index.types))
        @test index.systems == Set(["SWebPlant", "SWebLeaf", "SWebRate"])
        @test issubset(["time", "*", "leaf.*", "total", "k", "rate", "leaf.area", "leaf.A", "leaf.doubled"], index.paths)
    end

    @testset "codec" begin
        @test Cropbox.parseunit("K*d") == u"K*d"
        @test Cropbox.parseunit("m s⁻¹") == u"m/s"
        @test Cropbox.parseunit("μmol/mol") == u"μmol/mol" && Cropbox.parseunit("μmol/(m^2*s)") == u"μmol/m^2/s"
        @test Cropbox.parseunit("") === nothing && Cropbox.parseunit(nothing) === nothing
        @test_throws Cropbox.APIRequestError Cropbox.parseunit("Base.eval")
        @test_throws Cropbox.APIRequestError Cropbox.parseunit("nounit")
        for u in (u"m", u"K*d", u"μmol/mol", u"°C", u"percent", u"m/s^2")
            @test Cropbox.parseunit(Cropbox.unitlabel(u)) == u
        end
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
        @test Cropbox.parsebool("yes") === true && Cropbox.parsebool("off") === false && Cropbox.parsebool(1) === true

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
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "CSV"))
        @test_throws Cropbox.APIRequestError Cropbox.decode(Dict("type" => "DataFrame", "columns" => [Dict("name" => "a")], "rows" => [Dict("a" => 1)]))

        flat = Cropbox.decodeconfig(Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm"), "SWebAPI.c" => 3))
        nested = Cropbox.decodeconfig(Dict("SWebAPI" => Dict("a" => Dict("value" => 200, "unit" => "cm"), "c" => 3)))
        @test flat == nested == @config(:SWebAPI => (a = 200u"cm", c = 3))
        @test Cropbox.decodeconfig(nothing) == @config()
        @test Cropbox.decodeconfig(flat) === flat
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig([Dict("path" => "SWebAPI.a", "value" => 1)])
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig(Dict("a" => 1))
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig(Dict("a" => Dict("value" => 1, "unit" => "m")))
        @test_throws Cropbox.APIRequestError Cropbox.decodeconfig(Dict("Model.SWebAPI.a" => 1))
        @test Cropbox.decodeconfig(Dict("Soil" => Dict("type" => "clay"))) == @config(:Soil => :type => "clay")
        @test Dict(Cropbox.flatconfig(flat)) == Dict("SWebAPI.a" => 200u"cm", "SWebAPI.c" => 3)
        bounds = Cropbox.decodeconfig(Dict("SWebAPI.a" => [1, 2], "SWebAPI" => Dict("c" => Dict("lower" => 0, "upper" => 1, "unit" => "m"))); value = Cropbox.decodebounds)
        @test bounds[:SWebAPI][:a] == (1, 2) && bounds[:SWebAPI][:c] == (0u"m", 1u"m")
        @test_throws Cropbox.APIRequestError Cropbox.decodebounds([1])
        @test Dict(pairs(Cropbox.decodeoptions(Dict("MaxSteps" => 4, "Method" => "xnes")))) == Dict(:MaxSteps => 4, :Method => :xnes)
        @test Cropbox.decodeoptions(()) == (;) && Cropbox.decodeoptions(nothing) == (;)
        @test Cropbox.asobject(nothing) == Cropbox.asobject(()) == Cropbox.APIDict() && Cropbox.asobject((a = nothing,)) == Dict("a" => nothing)
        @test_throws Cropbox.APIRequestError Cropbox.asobject("x")
        @test Cropbox.decode([1, nothing, Dict("value" => 2, "unit" => "m")]) == [1, nothing, 2u"m"]

        @test Cropbox.encode(NaN) === nothing && Cropbox.encode(Inf) === nothing && Cropbox.encode(missing) === nothing
        @test Cropbox.encode(1 // 2) == 0.5 && Cropbox.encode(:x) == "x" && Cropbox.encode(Date(2024, 1, 2)) == "2024-01-02"
        @test Cropbox.encode(2u"m") == 2 && Cropbox.encode([1u"m", 2u"m"]) == [1, 2]
        @test Cropbox.encodevalue(2u"m") == Dict("value" => 2, "type" => "Int64", "unit" => "m")
        @test Cropbox.encodevalue(2u"m", u"cm") == Dict("value" => 200, "type" => "Int64", "unit" => "cm")
        @test Cropbox.encodevalue(2.5) == Dict("value" => 2.5, "type" => "Float64", "unit" => nothing)
        @test Cropbox.encodevalue(missing, u"m") == Dict("value" => nothing, "type" => nothing, "unit" => "m")
        @test Cropbox.encodevalue(1 // 2) == Dict("value" => 0.5, "type" => "Float64", "unit" => nothing)
        @test Cropbox.encodevalue(1u"m"; type = "Float64") == Dict("value" => 1, "type" => "Float64", "unit" => "m")
        @test Cropbox.wiretype(Union{Missing,Float64}) == "Float64" && Cropbox.wiretype(Missing) === nothing
        @test Cropbox.encode(@config(:S => :a => 1u"m")) == Dict("S" => Dict("a" => Dict("value" => 1, "type" => "Int64", "unit" => "m")))
        payload = Cropbox.tablepayload(DataFrame(t = [0, 1]u"hr", v = [1.5, NaN], s = [:x, :y]); model = "M")
        @test payload["status"] == "ok" && payload["model"] == "M" && payload["summary"]["nrow"] == 2
        @test payload["columns"] == [Dict("name" => "t", "type" => "Int64", "unit" => "hr"), Dict("name" => "v", "type" => "Float64", "unit" => nothing), Dict("name" => "s", "type" => "Symbol", "unit" => nothing)]
        @test payload["rows"] == [[0, 1.5, "x"], [1, nothing, "y"]]
        @test JSON.parse(JSON.json(payload))["rows"][2][2] === nothing
        roundtrip = Cropbox.decode(JSON.parse(JSON.json(Dict("type" => "DataFrame", "columns" => payload["columns"], "rows" => payload["rows"]))))
        @test roundtrip.t == [0, 1]u"hr" && roundtrip.v[1] == 1.5 && ismissing(roundtrip.v[2]) && roundtrip.s == [:x, :y]
    end

    @testset "requests" begin
        index = Cropbox.ModelIndex(describe(SWebAPI))
        r = Dict{String,Any}(
            "config" => Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm")),
            "stop" => Dict("value" => 1, "unit" => "hr"), "target" => ["a", "b"], "index" => "time",
            "seed" => 7, "nounit" => "true", "options" => Dict("x" => 1),
        )
        kw = Cropbox.simulationkwargs(SWebAPI, r; index)
        @test kw[:config] == @config(:SWebAPI => :a => 200u"cm")
        @test kw[:stop] == 1u"hr" && kw[:target] == ["a", "b"] && kw[:index] == "time"
        @test kw[:seed] == 7 && kw[:nounit] === true && kw[:options] == (x = 1,)
        merged = Cropbox.simulationkwargs(SWebAPI, r; config = :SWebAPI => (a = 3u"m", c = 5), options = (y = 2,))
        @test merged[:config] == @config(:SWebAPI => (a = 200u"cm", c = 5)) && merged[:options] == (y = 2, x = 1)
        multi = Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("configs" => [Dict("SWebAPI.a" => 1), Dict("SWebAPI.a" => 2)]); config = :SWebAPI => :c => 5)
        @test multi[:configs] == [@config(:SWebAPI => (a = 1, c = 5)), @config(:SWebAPI => (a = 2, c = 5))] && !haskey(multi, :config)
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("stop" => "g", "target" => Dict("len" => "length")); index)[:target] == [:len => "length"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("stop" => "nope"); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("target" => ["a", "zzz"]); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("target" => 5); index)
        # indexed and bundle paths only resolve at run time
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("target" => "leaves[1].area"); index)[:target] == "leaves[1].area"
        # every configuration is checked, by name or alias
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("config" => Dict("SWebAPI.length" => "2.5")); index)[:config] == @config(:SWebAPI => :length => 2.5)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("config" => Dict("SWebAPI.zzz" => 1)); index)
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("configs" => [Dict("SWebAPI.a" => 1), Dict("SWebAPI.zzz" => 1)]); index)
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("config" => Dict("Other.zzz" => 1)); index)[:config] == @config(:Other => :zzz => 1)
        # `meta` names configured systems or gives constant columns
        configured = Dict{String,Any}("config" => Dict("SWebAPI.a" => 1))
        @test Cropbox.simulationkwargs(SWebAPI, merge(configured, Dict("meta" => "SWebAPI")); index)[:meta] == :SWebAPI
        @test Cropbox.simulationkwargs(SWebAPI, merge(configured, Dict("meta" => Dict("site" => "A"))); index)[:meta] == [:site => "A"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("meta" => "SWebAPI"); index)
        # trusted Julia values from `request_defaults` pass through
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("target" => [:a, :b], "snap" => identity); index)[:target] == [:a, :b]
        @test Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("target" => ["zzz"]))[:target] == ["zzz"]
        @test_throws Cropbox.APIRequestError Cropbox.simulationkwargs(SWebAPI, Dict{String,Any}("configs" => Dict("SWebAPI.a" => 1)))
        @test Cropbox.decodestep(Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 3, "step" => 1, "unit" => "m")) == (:SWebAPI => :a => (1u"m":1u"m":3u"m"))
        @test Cropbox.decodestep(Dict("system" => "SWebAPI", "name" => "a", "values" => [1, 2])) == (:SWebAPI => :a => [1, 2])
        @test Cropbox.decodestep(Dict("path" => "SWebAPI.a", "values" => [100, 200], "unit" => "cm"), index) == (:SWebAPI => :a => [100, 200]u"cm")
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.zzz", "values" => [1]), index)
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "a", "values" => [1]))
        @test_throws Cropbox.APIRequestError Cropbox.decodestep(Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 3))
        plot = Cropbox.decodeplot(Dict("kind" => "scatter", "xlim" => [nothing, 5], "linestyles" => ["dash"], "title" => "t", "xunit" => "cm"))
        @test plot == Dict(:kind => :scatter, :xlim => (nothing, 5), :linestyle => [:dash], :title => "t", :xunit => u"cm")
        @test Cropbox.decodeplot(nothing) == Dict{Symbol,Any}()
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("backend" => "Gadfly"))
        @test_throws Cropbox.APIRequestError Cropbox.decodeplot(Dict("xlim" => [1]))
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
        d = describe(SWebAPI)
        index = Cropbox.ModelIndex(d)
        defaults = Dict(q["path"] => q["default"] for q in d["parameters"] if !isnothing(q["default"]["value"]))
        @test length(defaults) == 4 && Cropbox.simulate_payload(SWebAPI, Dict("config" => defaults, "stop" => 1, "target" => "b"); index)["rows"] == [[0, 1], [1, 1]]

        # nested systems: mixin and alias configuration paths, wildcards, `base` and `meta`
        index = Cropbox.ModelIndex(describe(SWebPlant))
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
        @test_throws Cropbox.APIRequestError Cropbox.calibrate_payload(SWebAPICalibration, merge(calibration, Dict("parameters" => Dict("SWebAPICalibration.zzz" => [0, 1]))); index = Cropbox.ModelIndex(describe(SWebAPICalibration)))

        v = Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "stop" => Dict("value" => 2, "unit" => "hr"), "plot" => Dict("kind" => "scatterline", "title" => "b over time")))
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
        @test occursin("<svg", Cropbox.visualize_payload(SWebAPI, Dict("data" => other, "x" => "day", "y" => "height"); index = Cropbox.ModelIndex(describe(SWebAPI)))["body"])
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("data" => other, "x" => "day", "y" => "b"))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("stop" => 2))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "backend" => "UnicodePlots"))
        @test_throws Cropbox.APIRequestError Cropbox.visualize_payload(SWebAPI, Dict("y" => "b", "plot" => Dict("backend" => "Makie")))

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
        @test w["visualize"]["x"]["default"] == "time" && w["visualize"]["y"]["default"] == ["b"]
        @test only(w["panels"]) == Dict("title" => "Panel 1", "x" => "time", "y" => ["b"], "kind" => "line")
        @test !haskey(w, "sweeps")

        ui = Dict("title" => "Custom", "outputs" => ["g"], "panels" => [Dict("title" => "Flag", "x" => "time", "y" => ["g"])],
            "stop" => Dict("value" => 3, "unit" => "hr"), "snap" => Dict("value" => 1, "unit" => "hr"), "sweeps" => [Dict("path" => "SWebAPI.a")])
        w2 = Cropbox.widgetpayload(SWebAPI; config = :SWebAPI => :a => 4u"m", ui)
        @test w2["title"] == "Custom" && [v["target"] for v in w2["outputs"]] == ["time", "g"]
        @test only(w2["panels"])["y"] == ["g"] && w2["simulation"]["stop"]["value"] == 3 && w2["sweeps"] == ui["sweeps"]
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
        @test_throws Cropbox.APIRequestError Cropbox.widgetpayload(SWebTable; ui = Dict("table_inputs" => [Dict("path" => "SWebTable.nope")]))
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
        @test JSON.parse(getroute("/api/dashboard")[3])["title"] == "SWebAPI Dashboard"
        schema = JSON.parse(getroute("/api/schema")[3])
        @test schema["contract_version"] == "0.2.0" && any(r -> r["path"] == "/api/simulate" && r["method"] == "POST", schema["routes"])
        @test haskey(schema["definitions"], "SimulationRequest")
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
        status, _, body = post("/api/simulate", Dict("target" => "a", "stop" => Dict("value" => 1, "unit" => "kg")))
        @test status == 500 && body["error"]["category"] == "execution" && body["error"]["code"] == "execution_failed"
        # values that cannot be decoded are the client's error, not an execution failure
        for bad in (Dict("seed" => "abc"), Dict("config" => Dict("SWebAPI.n" => Dict("value" => 1.5, "type" => "Int"))),
                    Dict("config" => Dict("SWebAPI.a" => Dict("value" => 1, "unit" => "nounit"))), Dict("meta" => "Nope"), Dict("base" => "nope"))
            status, _, body = post("/api/simulate", merge(Dict{String,Any}("target" => "a"), bad))
            @test status == 422 && body["error"]["category"] == "validation"
        end
        status, _, body = post("/api/visualize", Dict("y" => "b", "xstep" => Dict("path" => "SWebAPI.zzz", "values" => [1, 2])))
        @test status == 422 && occursin("zzz", body["error"]["message"])

        observed = Dict("type" => "CSV", "content" => "time (hr),b (m)\n0,3\n1,3\n2,3\n")
        status, _, body = post("/api/evaluate", Dict("observed" => observed, "target" => "b"))
        @test status == 200 && body["value"]["value"] == 0.0 && body["summary"]["nobs"] == 3
        status, _, body = post("/api/visualize", Dict("y" => "b"))
        @test status == 200 && body["format"] == "svg"

        ts = Cropbox.Service(SWebTable; dashboard = :none)
        @test Cropbox.respond(ts, "GET", "/")[1] == 404 && Cropbox.respond(ts, "GET", "/dashboard")[1] == 404
        status, _, body = Cropbox.respond(ts, "POST", "/api/simulate", JSON.json(Dict("config" => Dict("SWebTable.weather" => "/etc/passwd"), "target" => "T", "stop" => 1)))
        @test status == 422 && JSON.parse(body)["error"]["category"] == "validation"
        status, _, body = Cropbox.respond(ts, "POST", "/api/simulate", JSON.json(Dict("config" => Dict("SWebTable.weather" => weather_table), "target" => "T", "stop" => Dict("value" => 2, "unit" => "d"))))
        @test status == 200 && [r[2] for r in JSON.parse(body)["rows"]] == [10, 12, 14]

        custom = Cropbox.Service(SWebAPI; dashboard = "/ui")
        @test Cropbox.respond(custom, "GET", "/ui")[1] == 200 && Cropbox.respond(custom, "GET", "/")[1] == 404
        @test Cropbox.dashboardfrontend(false) isa Cropbox.NoDashboard
        @test_throws ErrorException Cropbox.dashboardfrontend(:bogus)
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
