using DataFrames
using Dates
using JSON

@testset "webapi" begin
    @system SWebAPI(Controller) begin
        a: length => 1 ~ preserve(parameter, u"m")
        b(a) => a ~ track(u"m")
    end

    request = Dict(
        "config_entries" => Dict("SWebAPI.a" => Dict("value" => 200, "unit" => "cm")),
        "stop" => Dict("value" => 1, "unit" => "hr"), "target" => ["a", "b"],
    )

    @testset "metadata and configuration" begin
        @test describe(DataFrame(a = [1])) isa DataFrame
        description = describe(SWebAPI)
        @test description["contract"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test description["model"]["name"] == "SWebAPI"
        parameter = only(description["parameters"])
        @test parameter["config_path"] == "SWebAPI.a"
        @test parameter["alias"] == "length"
        @test parameter["unit"] == "m"
        @test any(v -> v["name"] == "b" && v["dependencies"] == ["a"], description["variables"])

        normalized = Cropbox.normalize_request(SWebAPI, request)
        @test normalized["config"][:SWebAPI][:a] == 2u"m"
        @test normalized["stop"] == 1u"hr"
        @test normalized["target"] == [:a, :b]
        @test Cropbox.parse_api_unit("μmol m⁻² s⁻¹") == u"μmol/m^2/s"

        widgets = Cropbox.widget_payload(SWebAPI)
        @test any(c -> c["path"] == "SWebAPI.a" && c["kind"] == "number", widgets["controls"])
        @test widgets["visualize"]["y"]["default"] == ["b"]
        for path in ("/api/model", "/api/schema", "/api/openapi", "/api/dashboard")
            status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", path, "")
            @test status == 200
            @test content_type == "application/json; charset=utf-8"
            @test !isempty(JSON.parse(body))
        end
    end

    @testset "simulation, evaluation and calibration" begin
        result = Cropbox.simulate_payload(SWebAPI, request)
        @test result["status"] == "ok"
        @test result["columns"][2]["unit"] == "m"
        @test result["rows"] == [[0.0, 2.0, 2.0], [1.0, 2.0, 2.0]]

        observed = Dict(
            "type" => "DataFrame",
            "columns" => [Dict("name" => "time", "unit" => "hr"), Dict("name" => "b", "unit" => "m")],
            "rows" => [[0, 2], [1, 2]],
        )
        evaluation = merge(request, Dict("observed" => observed, "target" => "b", "metric" => "rmse"))
        result = Cropbox.evaluate_payload(SWebAPI, evaluation)
        @test result["value"]["value"] == 0
        @test result["value"]["unit"] == "m"
        @test result["summary"]["nobs"] == 2

        calibration = merge(evaluation, Dict(
            "parameters" => [Dict("path" => "SWebAPI.a", "lower" => 1.5, "upper" => 2.5, "unit" => "m")],
            "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent"),
        ))
        result = Cropbox.calibrate_payload(SWebAPI, calibration)
        @test result["operation"] == "calibrate"
        @test result["summary"]["nparameters"] == 1
        @test 1.5 <= result["config"]["SWebAPI"]["a"]["value"] <= 2.5
    end

    @testset "tables" begin
        table = Cropbox.parse_api_value(Dict(
            "type" => "CSV", "content" => "date,temperature\n2024-02-01,6.2\n",
            "columns" => [Dict("name" => "date", "type" => "Date"), Dict("name" => "temperature", "unit" => "°C")],
        ))
        @test table.date == [Date(2024, 2, 1)]
        @test table.temperature == [6.2u"°C"]
        payload = Cropbox.table_payload(DataFrame(a = [1.0, NaN, Inf]); model = "SWebAPI")
        @test JSON.parse(JSON.json(payload))["rows"] == [[1.0], [nothing], [nothing]]
        @test_throws Cropbox.APIRequestError Cropbox.parse_api_unit("Base.eval")
        @test_throws Cropbox.APIRequestError Cropbox.parse_api_value(Dict(
            "type" => "CSV", "content" => "\"value (:DefinitelyNotAType)\",other\n1,2\n",
        ))
    end

    @testset "visualization" begin
        plot_request = merge(request, Dict("x" => "time", "y" => ["a", "b"], "kind" => "line"))
        for key in ("linestyle", "linestyles")
            result = Cropbox.visualize_payload(SWebAPI,
                merge(plot_request, Dict("plot" => Dict(key => ["solid", "dash"]))))
            @test result["content_type"] == "image/svg+xml"
            @test occursin("<svg", result["body"])
            @test occursin("stroke-dasharray", result["body"])
        end
        result = Cropbox.visualize_payload(SWebAPI, Dict(
            "x" => "a", "y" => "b", "kind" => "line",
            "xstep" => Dict("path" => "SWebAPI.a", "start" => 1, "stop" => 2, "step" => 0.5, "unit" => "m"),
        ))
        @test result["status"] == "ok"
        @test occursin("<svg", result["body"])
    end

    @testset "HTTP and dashboard" begin
        for start in (serve, dashboard)
            server = start(SWebAPI; port = 0, async = true)
            try
                url = "http://127.0.0.1:$(Cropbox.HTTP.port(server))"
                page = Cropbox.HTTP.get("$url/dashboard"; read_idle_timeout = 180)
                @test page.status == 200
                @test occursin("Cropbox Dashboard", String(page.body))
                response = Cropbox.HTTP.post("$url/api/simulate", ["Content-Type" => "application/json"], JSON.json(request);
                    read_idle_timeout = 180)
                @test response.status == 200
                @test JSON.parse(String(response.body))["rows"][end] == [1.0, 2.0, 2.0]
            finally
                close(server)
            end
        end
    end

    @testset "errors" begin
        for (method, path, body, expected_status, category) in (
            ("GET", "/api/missing", "", 404, "routing"),
            ("POST", "/api/simulate", "{", 400, "syntax"),
            ("POST", "/api/evaluate", "{}", 422, "validation"),
        )
            status, _, response = Cropbox.route_api_response(SWebAPI, method, path, body)
            @test status == expected_status
            @test JSON.parse(response)["error"]["category"] == category
        end

        @system SWebAPIFailure(Controller) begin
            failed => error("model execution failed") ~ track
        end
        status, _, body = Cropbox.route_api_response(SWebAPIFailure, "POST", "/api/simulate",
            JSON.json(Dict("stop" => 0, "target" => "failed")))
        @test status == 500
        @test JSON.parse(body)["error"]["category"] == "execution"
    end
end
