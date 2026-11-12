# The example services, driven without a socket by the requests that the bundled dashboard sends, and compared
# with native calls. This loads Garlic and LeafGasExchange and runs a season of Garlic, so it is run by hand:
#
#     julia --project=examples/webapi examples/webapi/integration.jl
using Cropbox
using JSON
using Test

include(joinpath(@__DIR__, "profiles.jl"))

@testset "Web API example services" begin
    # `plot` options of a dashboard panel
    plotoptions(panel) = begin
        plot = Dict{String,Any}()
        for (limit, lower, upper) in (("xlim", "xmin", "xmax"), ("ylim", "ymin", "ymax"))
            bounds = [get(panel, lower, nothing), get(panel, upper, nothing)]
            all(isnothing, bounds) || (plot[limit] = bounds)
        end
        styles = get(panel, "linestyles", [])
        !isempty(styles) && length(styles) == length(panel["y"]) && (plot["linestyle"] = styles)
        plot
    end

    # `override` is a parameter the profile sets by one of its names (its own, a mixin's, an alias), which a client
    # sets through another one that Cropbox would read after the profile's
    for (name, target, x, override) in (
            ("cherry", "F", "time", ("CherryBloomCF.temperature_threshold", :CherryBloomCF, :Tc, 12, "°C")),
            ("gasexchange", "A_net", "Ci", ("ModelC3BB.carbon_dioxide", :ModelC3BB, :CO2, 800, "μmol/mol")),
            ("garlic", "total_mass", "DAP", ("LeafInitiation.storage_days", :Phenology, :SD, 100, "d")))
        @testset "$name" begin
            p = WebAPIExamples.profile(name)
            service = Cropbox.Service(p.system; p.config, p.ui, p.request_defaults)
            getjson(path) = JSON.parse(Cropbox.respond(service, "GET", path)[3])
            postjson(path, request) = begin
                status, _, body = Cropbox.respond(service, "POST", path, JSON.json(request))
                status == 200 || error("POST $path returned HTTP $status: $body")
                JSON.parse(body)
            end

            model = getjson("/api/model")
            @test !isempty(model["parameters"]) && !isempty(model["variables"])
            @test model == JSON.parse(JSON.json(describe(p.system; config = service.config)))
            @test allunique(q["path"] for q in model["parameters"])

            # every default of the description can be sent back as a configuration
            defaults = Dict{String,Any}(q["path"] => q["default"] for q in model["parameters"] if !isnothing(q["default"]) && !isnothing(q["default"]["value"]))
            @test !isempty(defaults)
            decodes(path) = try
                Cropbox.simulationkwargs(Dict{String,Any}("config" => Dict(path => defaults[path])); index = service.index)
                true
            catch
                false
            end
            @test filter(!decodes, sort!(collect(keys(defaults)))) == []

            # the client's value is the one in effect
            spelling, system, parameter, value, unit = override
            client = Dict(spelling => Dict("value" => value, "unit" => unit))
            merged = Cropbox.simulationkwargs(Dict{String,Any}("config" => client); config = service.config, index = service.index)[:config]
            @test merged[system][parameter] == Cropbox.unitfy(value, Cropbox.parseunit(unit)) != service.config[system][parameter]

            dashboard = getjson("/api/dashboard")
            outputs = [o["target"] for o in dashboard["outputs"]]
            @test first(outputs) == "time" && target in outputs && x in outputs
            panels = dashboard["panels"]
            # panels only plot variables the dashboard offers as outputs
            @test all(panel -> issubset(vcat(panel["x"], panel["y"]), outputs), panels)

            # one simulation covers the selected output columns and every panel, from the `stop` the service defaults to
            stop = dashboard["simulation"]["stop"]
            @test stop == JSON.parse(JSON.json(p.request_defaults["stop"])) && isnothing(dashboard["simulation"]["snap"])
            targets = unique(vcat(outputs[1:min(5, end)], target, x, (vcat(panel["x"], panel["y"]) for panel in panels)...))
            result = postjson("/api/simulate", Dict("config" => Dict(), "stop" => stop, "target" => targets))
            columns = [c["name"] for c in result["columns"]]
            @test result["status"] == "ok" && !isempty(result["rows"]) && issubset(targets, columns) && first(columns) == "time"
            @test first(result["columns"])["unit"] == first(dashboard["outputs"])["unit"]
            i = findfirst(==(target), columns)
            @test all(row -> row[i] isa Number && isfinite(row[i]), result["rows"])

            # panels plot that table, except sweeps, which simulate again
            for panel in panels
                kind = get(panel, "kind", "line")
                sweep = get(panel, "xstep", nothing)
                request = if isnothing(sweep) || isempty(sweep)
                    indices = Int[findfirst(==(v), columns) for v in unique(vcat(panel["x"], panel["y"]))]
                    data = Dict("type" => "DataFrame", "columns" => result["columns"][indices], "rows" => [row[indices] for row in result["rows"]])
                    Dict("data" => data, "x" => panel["x"], "y" => panel["y"], "kind" => kind, "plot" => plotoptions(panel))
                else
                    spec = only(filter(s -> s["path"] == sweep, dashboard["sweeps"]))
                    xstep = Dict(k => spec[k] for k in ("path", "values", "start", "stop", "step", "unit") if !isnothing(get(spec, k, nothing)))
                    Dict("config" => Dict(), "stop" => stop, "x" => panel["x"], "y" => panel["y"], "kind" => kind, "xstep" => xstep, "plot" => plotoptions(panel))
                end
                @test occursin("<svg", postjson("/api/visualize", request)["body"])
            end

            # the season-long Garlic run is not repeated for the remaining checks
            if name != "garlic"
                # the service returns the table of the native call
                native = simulate(p.system; p.config, stop = Cropbox.unitfy(stop["value"], Cropbox.parseunit(stop["unit"])), target = [Symbol(target)], verbose = false)
                @test [row[i] for row in result["rows"]] == Cropbox.deunitfy(native[!, target])
                @test occursin("<svg", postjson("/api/visualize", Dict("x" => x, "y" => [target], "kind" => "line"))["body"])
                @test postjson("/api/simulate", Dict("config" => defaults, "stop" => stop, "target" => [target]))["rows"] ==
                    [[row[1], row[i]] for row in result["rows"]]
                @test postjson("/api/simulate", Dict("config" => client, "stop" => 1, "target" => [string(parameter)]))["rows"][1][2] == value
            end
        end
    end
end
