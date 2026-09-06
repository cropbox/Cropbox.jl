# Exercise all three example profiles through real loopback HTTP requests.
using Cropbox
using HTTP
using JSON3
using Test

include("server.jl")

"""Send a JSON request to a running example and verify its HTTP status."""
function request_json(base, method, route, request=nothing)
    headers = ["Content-Type" => "application/json"]
    body = isnothing(request) ? "" : JSON3.write(request)
    response = HTTP.request(method, base * route, headers, body; readtimeout=180)
    @test response.status == 200
    JSON3.read(String(response.body), Dict{String,Any})
end

@testset "Web API application examples" begin
    for (name, target, index) in (("cherry", "F", "time"),
                                  ("gasexchange", "A_net", "Ci"),
                                  ("garlic", "total_mass", "DAP"))
        @testset "$name" begin
            p = WebAPIExamples.profile(name)
            model = describe(p.system; p.config)
            @test !isempty(model["variables"])
            @test !isempty(model["parameters"])
            server = serve(p.system; p.config, p.ui, p.request_defaults, port=0, async=true)
            base = "http://127.0.0.1:$(HTTP.port(server))"
            try
                live = request_json(base, "GET", "/api/model")
                @test live == JSON3.read(JSON3.write(model), Dict{String,Any})
                for route in ("/api/schema", "/api/openapi")
                    @test !isempty(request_json(base, "GET", route))
                end
                dashboard = request_json(base, "GET", "/api/dashboard")
                time_output = only(filter(v -> v["target_path"] == "time", dashboard["outputs"]))
                @test occursin("run-button", String(HTTP.get(base * "/dashboard").body))
                result = request_json(base, "POST", "/api/simulate", Dict("target" => ["time", target]))
                @test result["status"] == "ok"
                @test !isempty(result["rows"])
                @test first(result["columns"])["unit"] == time_output["unit"]
                column = findfirst(c -> c["name"] == target, result["columns"])
                @test !isnothing(column)
                @test all(row -> row[column] isa Number && isfinite(row[column]), result["rows"])
                plot = request_json(base, "POST", "/api/visualize",
                    Dict("x" => index, "y" => [target], "kind" => "line"))
                @test plot["content_type"] == "image/svg+xml"
                @test occursin("<svg", plot["body"])
                @test occursin("</svg>", plot["body"])
                if haskey(ENV, "CROPBOX_MCP_PYTHON")
                    python = ENV["CROPBOX_MCP_PYTHON"]
                    script = joinpath(@__DIR__, "mcp", "check.py")
                    @test success(`$python $script --url $base --target $target --x $index`)
                end
            finally
                close(server)
            end
        end
    end
end
