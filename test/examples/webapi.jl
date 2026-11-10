using Cropbox
using JSON
using Test

# The example services of `examples/webapi`, driven with the requests the bundled dashboard sends.
include(joinpath(@__DIR__, "..", "..", "examples", "webapi", "profiles.jl"))

@testset "webapi" begin
    # `plot` options of a dashboard panel
    plotoptions(panel) = begin
        plot = Dict{String,Any}()
        for (limit, lower, upper) in (("xlim", "xmin", "xmax"), ("ylim", "ymin", "ymax"))
            bounds = [get(panel, lower, nothing), get(panel, upper, nothing)]
            all(isnothing, bounds) || (plot[limit] = bounds)
        end
        styles = get(panel, "linestyles", [])
        !isempty(styles) && length(styles) == length(panel["y"]) && (plot["linestyles"] = styles)
        plot
    end

    for (name, target, x) in (("cherry", "F", "time"), ("gasexchange", "A_net", "Ci"), ("garlic", "total_mass", "DAP"))
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

            # every default of the description can be sent back as a configuration
            defaults = Dict{String,Any}(q["path"] => q["default"] for q in model["parameters"] if !isnothing(q["default"]) && !isnothing(q["default"]["value"]))
            @test !isempty(defaults)
            decodes(path) = try
                Cropbox.simulationkwargs(p.system, Dict{String,Any}("config" => Dict(path => defaults[path])); index = service.index)
                true
            catch
                false
            end
            @test filter(!decodes, sort!(collect(keys(defaults)))) == []

            dashboard = getjson("/api/dashboard")
            outputs = [o["target"] for o in dashboard["outputs"]]
            @test first(outputs) == "time" && target in outputs && x in outputs
            panels = dashboard["panels"]
            # panels only plot variables the dashboard offers as outputs
            @test all(panel -> issubset(vcat(panel["x"], panel["y"]), outputs), panels)

            # one simulation covers the selected output columns and every panel
            stop = dashboard["simulation"]["stop"]
            stop["value"] isa Number || (stop = stop["value"])
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
                @test occursin("<svg", postjson("/api/visualize", Dict("x" => x, "y" => [target], "kind" => "line"))["body"])
                @test postjson("/api/simulate", Dict("config" => defaults, "stop" => stop, "target" => [target]))["rows"] ==
                    [[row[1], row[i]] for row in result["rows"]]
            end
        end
    end
end
