using CSV
using DataFrames
using Dates
using JSON3
using TimeZones

const WEBAPI_HAS_GARLIC = !isnothing(Base.find_package("Garlic"))
const WEBAPI_HAS_LEAFGASEXCHANGE = !isnothing(Base.find_package("LeafGasExchange"))
const WEBAPI_HAS_SIMPLECROP = !isnothing(Base.find_package("SimpleCrop"))

WEBAPI_HAS_GARLIC && (@eval using Garlic)
WEBAPI_HAS_LEAFGASEXCHANGE && (@eval using LeafGasExchange)
WEBAPI_HAS_SIMPLECROP && (@eval using SimpleCrop)

const API_TEST_ATOL = 1e-9
# Cold compilation under coverage can exceed 30 seconds on CI runners.
const API_TEST_READTIMEOUT = 180

api_same_value(a, b; atol=API_TEST_ATOL) =
    a isa Number && b isa Number ? isapprox(a, b; atol, rtol=atol) : a == b

function assert_table_equivalent(response, direct; atol=API_TEST_ATOL)
    @test response["status"] == "ok"
    @test response["summary"]["nrow"] == nrow(direct)
    @test [c["name"] for c in response["columns"]] == names(direct)
    units = try
        Cropbox.unittype(direct)
    catch
        nothing
    end
    if !isnothing(units)
        @test [c["unit"] for c in response["columns"]] == Cropbox.encode_api_unit.(units)
    end
    values_match = true
    for i in 1:nrow(direct)
        for (j, name) in enumerate(names(direct))
            values_match &= api_same_value(response["rows"][i][j], Cropbox.encode_api_plain(Cropbox.deunitfy(direct[i, Symbol(name)])); atol)
        end
    end
    @test values_match
end

function merge_api_config(base, fitted)
    merged = JSON3.read(JSON3.write(base), Dict{String,Any})
    for (system, fields) in fitted
        target = get!(merged, system, Dict{String,Any}())
        for (name, value) in fields
            target[name] = value
        end
    end
    merged
end

api_server_url(server) = "http://127.0.0.1:$(Cropbox.HTTP.port(server))"

function http_get_json(base_url, path; readtimeout=API_TEST_READTIMEOUT)
    response = Cropbox.HTTP.get("$base_url$path"; readtimeout)
    JSON3.read(String(response.body), Dict{String,Any}), response
end

function http_post_json(base_url, path, payload; readtimeout=API_TEST_READTIMEOUT)
    response = Cropbox.HTTP.request(
        "POST",
        "$base_url$path",
        ["Content-Type" => "application/json"],
        JSON3.write(payload);
        readtimeout,
    )
    JSON3.read(String(response.body), Dict{String,Any}), response
end

module WebAPIPheno

using Cropbox
using TimeZones
import Dates

@system Estimator begin
    year ~ preserve::int(parameter)
    Ds: start_date_offset => 270 ~ preserve::int(u"d")
    De: end_date_offset => 150 ~ preserve::int(u"d")
    tz: timezone => tz"UTC" ~ preserve::TimeZone(parameter)
    t0(year, tz, Ds): start_date => begin
        ZonedDateTime(year-1, 1, 1, tz) + Dates.Day(Ds)
    end ~ preserve::datetime
    t1(year, tz, De): end_date => begin
        ZonedDateTime(year, 1, 1, tz) + Dates.Day(De)
    end ~ preserve::datetime
    calendar(context, init=t0') ~ ::Calendar
    t(calendar.time): current_date ~ track::datetime
    s: store ~ provide(init=t, parameter)
    match => false ~ flag
    stop(m=match, t, t1) => (m || t >= t1) ~ flag
    T: temperature ~ drive(from=s, by=:tavg, u"°C")
end

estimate(S::Type{<:Estimator}, years; config, index=[:year, "calendar.time"], target=[:match], stop=:stop, kwargs...) = begin
    configs = @config config + !(S => :year => years)
    simulate(S; index, target, configs, stop, snap=:match, kwargs...)
end

@system BetaFuncEstimator(BetaFunction, Estimator, Controller) <: Estimator begin
    Rg: growth_requirement ~ preserve(parameter)
    Cg(ΔT): growth_cumulated ~ accumulate
    match(Cg, Rg) => Cg >= Rg ~ flag
end

@system UnitMetadata(Controller) begin
    "Parameter declared in a package-style module."
    size => 2 ~ preserve(parameter, u"m")
    reported_size(size) => size ~ track(u"m")
end

end

@testset "webapi" begin
    @system SWebAPI(Controller) begin
        "Configurable length used to test unit-aware dashboard controls."
        a => 1 ~ preserve(parameter, u"m")
        "Tracked output that mirrors the configured length."
        b(a) => a ~ track(u"m")
    end

    @testset "describe" begin
        @test Cropbox.parse_api_unit("μmol mol⁻¹") == u"μmol/mol"
        @test Cropbox.parse_api_unit("μmol m⁻² s⁻¹") == u"μmol/m^2/s"
        @test Cropbox.parse_api_unit(Cropbox.encode_api_unit(u"d/K")) == u"d/K"
        @test Cropbox.parse_api_unit(Cropbox.encode_api_unit(u"cd*K")) == u"cd*K"
        @test Cropbox.parse_api_unit(Cropbox.encode_api_unit(u"percent")) == u"percent"
        @test Cropbox.parse_api_value(Dict("value" => "calendar.count", "unit" => "")) == "calendar.count"
        converted = Cropbox.encode_api_value(100u"cm", u"m")
        @test converted["value"] == 1.0
        @test converted["type"] == "Float64"
        @test converted["unit"] == "m"
        @test describe(DataFrame(a=[1, 2])) isa DataFrame
        for name in (
            :describe,
            :serve,
            :dashboard,
        )
            @test name in names(Cropbox)
        end

        for name in (
            :API_CONTRACT_VERSION,
            :widget_payload,
            :normalize_request,
            :simulate_payload,
            :visualize_payload,
            :evaluate_payload,
            :calibrate_payload,
            :external_table_payload,
        )
            @test isdefined(Cropbox, name)
            @test !(name in names(Cropbox))
        end

        d = Cropbox.describe(SWebAPI)
        @test Set(keys(d)) == Set(["contract", "model", "systems", "parameters", "variables", "tables"])
        @test d["contract"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test d["model"]["name"] == "SWebAPI"
        module_description = Cropbox.describe(WebAPIPheno.UnitMetadata)
        module_parameter = only(module_description["parameters"])
        @test module_parameter["unit"] == "m"
        @test module_parameter["default"]["unit"] == "m"
        @test module_parameter["description"] == "Parameter declared in a package-style module."
        @test any(s -> s["name"] == "SWebAPI" && s["root"] == true && s["access_path"] == "", d["systems"])
        @test any(p -> p["name"] == "a" &&
                       p["config_path"] == "SWebAPI.a" &&
                       p["declared_path"] == "SWebAPI.a" &&
                       p["accepted_config_paths"] == ["SWebAPI.a"] &&
                       p["unit"] == "m" &&
                       p["state"] == "preserve" &&
                       isempty(p["tags"]) &&
                       occursin("Configurable length", p["description"]), d["parameters"])
        @test any(v -> v["name"] == "b" &&
                       v["target_path"] == "b" &&
                       v["declared_path"] == "SWebAPI.b" &&
                       v["type"] == "Float64" &&
                       v["unit"] == "m" &&
                       v["state"] == "track" &&
                       isempty(v["tags"]) &&
                       v["dependencies"] == ["a"] &&
                       occursin("Tracked output", v["description"]), d["variables"])

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/model", "")
        routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed["contract"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test routed["model"]["name"] == "SWebAPI"
        @test !haskey(routed, "operations")
    end

    @testset "simulate payload" begin
        request = Dict(
            "config" => Dict(
                "SWebAPI" => Dict(
                    "a" => Dict("value" => 2, "unit" => "m"),
                ),
            ),
            "stop" => Dict("value" => 2, "unit" => "hr"),
            "target" => ["a", "b"],
        )

        normalized = Cropbox.normalize_request(SWebAPI, request)
        @test normalized["config"][:SWebAPI][:a] == 2u"m"
        @test normalized["stop"] == 2u"hr"
        @test normalized["target"] == [:a, :b]

        response = Cropbox.simulate_payload(SWebAPI, request)
        @test response["status"] == "ok"
        @test response["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test response["summary"]["nrow"] == 3
        @test response["columns"][2]["name"] == "a"
        @test response["columns"][2]["unit"] == "m"
        @test response["rows"][end] == Any[2.0, 2.0, 2.0]

        entry_request = Dict(
            "config_entries" => [
                Dict("path" => "SWebAPI.a", "value" => Dict("value" => 3, "unit" => "m")),
            ],
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "target" => ["a", "b"],
        )
        entry_normalized = Cropbox.normalize_request(SWebAPI, entry_request)
        @test entry_normalized["config"][:SWebAPI][:a] == 3u"m"
        entry_response = Cropbox.simulate_payload(SWebAPI, entry_request)
        @test entry_response["status"] == "ok"
        @test entry_response["rows"][end] == Any[1.0, 3.0, 3.0]

        entry_map_request = Dict(
            "config_entries" => Dict("SWebAPI.a" => Dict("value" => 6, "unit" => "m")),
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "target" => ["a", "b"],
        )
        entry_map_response = Cropbox.simulate_payload(SWebAPI, entry_map_request)
        @test entry_map_response["rows"][end] == Any[1.0, 6.0, 6.0]

        merged_request = Dict(
            "config" => Dict("SWebAPI" => Dict("a" => Dict("value" => 2, "unit" => "m"))),
            "config_entries" => [
                Dict("system" => "SWebAPI", "name" => "a", "value" => Dict("value" => 5, "unit" => "m")),
            ],
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "target" => ["a", "b"],
        )
        merged_response = Cropbox.simulate_payload(SWebAPI, merged_request)
        @test merged_response["rows"][end] == Any[1.0, 5.0, 5.0]

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "POST", "/api/simulate", JSON3.write(request))
        routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed["status"] == "ok"

        default_request = Dict(
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "target" => ["a", "b"],
        )
        status, _, body = Cropbox.route_api_response(
            SWebAPI,
            "POST",
            "/api/simulate",
            JSON3.write(default_request);
            config=:SWebAPI => :a => 4u"m",
        )
        default_routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test default_routed["rows"][end] == Any[1.0, 4.0, 4.0]
    end

    @testset "serve HTTP round trip" begin
        server = Cropbox.serve(SWebAPI; host="127.0.0.1", port=0, async=true)
        try
            url = "http://127.0.0.1:$(Cropbox.HTTP.port(server))"

            model_response = Cropbox.HTTP.get("$url/api/model"; readtimeout=API_TEST_READTIMEOUT)
            model = JSON3.read(String(model_response.body), Dict{String,Any})
            @test model_response.status == 200
            @test model["model"]["name"] == "SWebAPI"
            @test any(p -> p["config_path"] == "SWebAPI.a" &&
                           occursin("Configurable length", p["description"]) &&
                           p["unit"] == "m", model["parameters"])
            @test !haskey(model, "operations")

            schema_response = Cropbox.HTTP.get("$url/api/schema"; readtimeout=API_TEST_READTIMEOUT)
            schema = JSON3.read(String(schema_response.body), Dict{String,Any})
            @test schema_response.status == 200
            @test schema["contract_version"] == Cropbox.API_CONTRACT_VERSION
            @test haskey(schema["definitions"], "StepSelection")
            @test schema["definitions"]["WidgetPayload"]["properties"]["controls"]["items"]["\$ref"] == "#/definitions/WidgetControl"
            @test schema["definitions"]["WidgetControl"]["properties"]["source"]["enum"] == ["dsl", "runtime"]
            @test any(r -> r["path"] == "/api/dashboard" && r["response"] == "WidgetPayload", schema["routes"])

            openapi_response = Cropbox.HTTP.get("$url/api/openapi"; readtimeout=API_TEST_READTIMEOUT)
            openapi = JSON3.read(String(openapi_response.body), Dict{String,Any})
            @test openapi_response.status == 200
            @test openapi["openapi"] == "3.1.0"
            @test haskey(openapi["paths"], "/api/dashboard")
            @test haskey(openapi["paths"], "/api/docs")
            @test haskey(openapi["components"]["schemas"], "StepSelection")
            @test openapi["components"]["schemas"]["WidgetPayload"]["properties"]["controls"]["items"]["\$ref"] == "#/components/schemas/WidgetControl"
            @test openapi["paths"]["/api/model"]["get"]["responses"]["200"]["content"]["application/json"]["examples"]["model_excerpt"]["value"]["model"]["name"] == "SWebAPI"
            @test openapi["paths"]["/api/model"]["get"]["responses"]["200"]["content"]["application/json"]["examples"]["model_excerpt"]["value"]["parameters"][1]["unit"] == "m"
            @test openapi["paths"]["/api/simulate"]["post"]["requestBody"]["content"]["application/json"]["examples"]["unit_config_entry"]["value"]["config_entries"][1]["path"] == "SWebAPI.a"

            docs_response = Cropbox.HTTP.get("$url/api/docs"; readtimeout=API_TEST_READTIMEOUT)
            docs = String(docs_response.body)
            @test docs_response.status == 200
            @test occursin("SwaggerUIBundle", docs)
            @test occursin("/api/openapi", docs)

            dashboard_schema_response = Cropbox.HTTP.get("$url/api/dashboard"; readtimeout=API_TEST_READTIMEOUT)
            dashboard_schema = JSON3.read(String(dashboard_schema_response.body), Dict{String,Any})
            @test dashboard_schema_response.status == 200
            @test dashboard_schema["model"]["name"] == "SWebAPI"
            @test !haskey(dashboard_schema, "manipulate")
            @test !haskey(dashboard_schema, "evaluate")
            @test !haskey(dashboard_schema, "calibrate")

            request = Dict(
                "config_entries" => Dict("SWebAPI.a" => Dict("value" => 7, "unit" => "m")),
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "target" => ["a", "b"],
            )
            simulation_response = Cropbox.HTTP.request(
                "POST",
                "$url/api/simulate",
                ["Content-Type" => "application/json"],
                JSON3.write(request);
                readtimeout=API_TEST_READTIMEOUT,
            )
            simulation = JSON3.read(String(simulation_response.body), Dict{String,Any})
            @test simulation_response.status == 200
            @test simulation["status"] == "ok"
            @test simulation["rows"][end] == Any[1.0, 7.0, 7.0]

            plot_response = Cropbox.HTTP.request(
                "POST",
                "$url/api/visualize",
                ["Content-Type" => "application/json"],
                JSON3.write(merge(request, Dict("x" => "time", "y" => "b", "kind" => "line")));
                readtimeout=API_TEST_READTIMEOUT,
            )
            plot = JSON3.read(String(plot_response.body), Dict{String,Any})
            @test plot_response.status == 200
            @test plot["status"] == "ok"
            @test plot["content_type"] == "image/svg+xml"
            @test occursin("<svg", plot["body"])

            observed = Dict(
                "type" => "DataFrame",
                "columns" => [
                    Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                    Dict("name" => "b", "type" => "Float64", "unit" => "m"),
                ],
                "rows" => [[0, 7], [1, 7]],
            )
            evaluation_response = Cropbox.HTTP.request(
                "POST",
                "$url/api/evaluate",
                ["Content-Type" => "application/json"],
                JSON3.write(merge(request, Dict("observed" => observed, "target" => "b", "metric" => "rmse")));
                readtimeout=API_TEST_READTIMEOUT,
            )
            evaluation = JSON3.read(String(evaluation_response.body), Dict{String,Any})
            @test evaluation_response.status == 200
            @test evaluation["operation"] == "evaluate"
            @test evaluation["value"]["value"] == 0.0

            calibration_response = Cropbox.HTTP.request(
                "POST",
                "$url/api/calibrate",
                ["Content-Type" => "application/json"],
                JSON3.write(Dict(
                    "observed" => observed,
                    "target" => "b",
                    "stop" => Dict("value" => 1, "unit" => "hr"),
                    "metric" => "rmse",
                    "parameters" => [
                        Dict(
                            "path" => "SWebAPI.a",
                            "lower" => 6,
                            "upper" => 8,
                            "unit" => "m",
                        ),
                    ],
                    "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent"),
                ));
                readtimeout=API_TEST_READTIMEOUT,
            )
            calibration = JSON3.read(String(calibration_response.body), Dict{String,Any})
            @test calibration_response.status == 200
            @test calibration["operation"] == "calibrate"
            @test 6 <= calibration["config"]["SWebAPI"]["a"]["value"] <= 8

            dashboard_response = Cropbox.HTTP.get("$url/"; readtimeout=API_TEST_READTIMEOUT)
            dashboard = String(dashboard_response.body)
            @test dashboard_response.status == 200
            @test occursin("<h2>Panels</h2>", dashboard)
            @test occursin("aria-label=\"Add panel\"", dashboard)
            @test occursin("aria-label=\"Download results as CSV\"", dashboard)
            @test occursin("data-panel-y-option", dashboard)
            @test !occursin("Request preview", dashboard)
            @test !occursin("Evaluation / calibration", dashboard)

            dashboard_alias_response = Cropbox.HTTP.get("$url/dashboard"; readtimeout=API_TEST_READTIMEOUT)
            dashboard_alias = String(dashboard_alias_response.body)
            @test dashboard_alias_response.status == 200
            @test occursin("<h2>Panels</h2>", dashboard_alias)
        finally
            close(server)
        end

        api_only_server = Cropbox.serve(SWebAPI; host="127.0.0.1", port=0, async=true, dashboard=false)
        try
            api_only_url = "http://127.0.0.1:$(Cropbox.HTTP.port(api_only_server))"

            dashboard_response = Cropbox.HTTP.get("$api_only_url/"; readtimeout=API_TEST_READTIMEOUT, status_exception=false)
            dashboard_error = JSON3.read(String(dashboard_response.body), Dict{String,Any})
            @test dashboard_response.status == 404
            @test dashboard_error["error"]["category"] == "routing"

            dashboard_schema_response = Cropbox.HTTP.get("$api_only_url/api/dashboard"; readtimeout=API_TEST_READTIMEOUT)
            dashboard_schema = JSON3.read(String(dashboard_schema_response.body), Dict{String,Any})
            @test dashboard_schema_response.status == 200
            @test dashboard_schema["model"]["name"] == "SWebAPI"
        finally
            close(api_only_server)
        end
    end

    @testset "serve default options" begin
        @system SWebAPIServeOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::int(override)
            c(a, b) => a + b ~ track
        end

        server = Cropbox.serve(
            SWebAPIServeOptions;
            host="127.0.0.1",
            port=0,
            async=true,
            options=(; a=1, b=2),
        )
        try
            url = api_server_url(server)
            request = Dict(
                "stop" => 1,
                "target" => ["a", "b", "c"],
            )
            routed, response = http_post_json(url, "/api/simulate", request)
            direct = simulate(
                SWebAPIServeOptions;
                options=(; a=1, b=2),
                stop=1,
                target=[:a, :b, :c],
                verbose=false,
            )
            @test response.status == 200
            assert_table_equivalent(routed, direct)

            override_request = merge(request, Dict("options" => Dict("b" => 4)))
            override_routed, override_response = http_post_json(url, "/api/simulate", override_request)
            override_direct = simulate(
                SWebAPIServeOptions;
                options=(; a=1, b=4),
                stop=1,
                target=[:a, :b, :c],
                verbose=false,
            )
            @test override_response.status == 200
            assert_table_equivalent(override_routed, override_direct)
            @test override_routed["rows"][end][4] == 5
        finally
            close(server)
        end

        request_defaults = Dict{String,Any}(
            "stop" => 2,
            "snap" => (s -> true),
            "target" => ["a", "b", "c"],
        )
        status, _, body = Cropbox.route_api_response(
            SWebAPIServeOptions,
            "POST",
            "/api/simulate",
            "{}";
            options=(; a=1, b=2),
            request_defaults,
        )
        defaulted = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test defaulted["summary"]["nrow"] == 3
        @test [column["name"] for column in defaulted["columns"]] == ["time", "a", "b", "c"]

        status, _, body = Cropbox.route_api_response(
            SWebAPIServeOptions,
            "POST",
            "/api/simulate",
            JSON3.write(Dict("stop" => 1));
            options=(; a=1, b=2),
            request_defaults,
        )
        overridden = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test overridden["summary"]["nrow"] == 2

        merged = Cropbox.apply_request_defaults(
            Dict(
                "config_entries" => [
                    Dict("path" => "Weather.s", "value" => "default-weather"),
                    Dict("path" => "Model.a", "value" => 1),
                ],
            ),
            Dict(
                "config_entries" => [
                    Dict("path" => "Weather.s", "value" => "uploaded-weather"),
                    Dict("path" => "Model.b", "value" => 2),
                ],
            ),
        )
        @test length(merged["config_entries"]) == 3
        @test only(filter(e -> e["path"] == "Weather.s", merged["config_entries"]))["value"] == "uploaded-weather"
        @test any(e -> e["path"] == "Model.a", merged["config_entries"])
        @test any(e -> e["path"] == "Model.b", merged["config_entries"])
    end

    @testset "evaluate payload" begin
        request = Dict(
            "config" => Dict(
                "SWebAPI" => Dict(
                    "a" => Dict("value" => 2, "unit" => "m"),
                ),
            ),
            "observed" => Dict(
                "type" => "DataFrame",
                "columns" => [
                    Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                    Dict("name" => "b", "type" => "Float64", "unit" => "m"),
                ],
                "rows" => [
                    [0, 2],
                    [1, 2],
                    [2, 2],
                ],
            ),
            "target" => "b",
            "stop" => Dict("value" => 2, "unit" => "hr"),
            "metric" => "rmse",
        )

        response = Cropbox.evaluate_payload(SWebAPI, request)
        @test response["status"] == "ok"
        @test response["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test response["operation"] == "evaluate"
        @test response["metric"] == "rmse"
        @test response["value"]["value"] == 0.0
        @test response["value"]["unit"] == "m"
        @test response["summary"]["nobs"] == 3

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "POST", "/api/evaluate", JSON3.write(request))
        routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed["status"] == "ok"
        @test routed["operation"] == "evaluate"

        csv_request = deepcopy(request)
        csv_request["observed"] = Dict(
            "type" => "CSV",
            "filename" => "observed.csv",
            "content" => "time,b\n0,2\n1,2\n2,2\n",
            "columns" => [
                Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                Dict("name" => "b", "type" => "Float64", "unit" => "m"),
            ],
        )
        csv_response = Cropbox.evaluate_payload(SWebAPI, csv_request)
        @test csv_response["status"] == "ok"
        @test csv_response["operation"] == "evaluate"
        @test csv_response["value"]["value"] == 0.0

        configs_request = deepcopy(request)
        delete!(configs_request, "config")
        configs_request["configs"] = [request["config"]]
        configs_response = Cropbox.evaluate_payload(
            SWebAPI,
            configs_request;
            config=(:Clock => :step => 1u"hr",),
        )
        @test configs_response["status"] == "ok"
        @test configs_response["value"]["value"] == 0.0

        @system SWebAPIEvaluationSnap(Controller) begin
            x => 1 ~ accumulate
        end
        snap_obs = DataFrame(time=[0, 1, 2]u"hr", x=[0, 100, 2])
        snap_value = evaluate(
            SWebAPIEvaluationSnap,
            snap_obs;
            target=:x,
            stop=2u"hr",
            snap=2u"hr",
        )
        @test snap_value > 10
    end

    @testset "calibrate payload" begin
        @system SWebAPICalibration(Controller) begin
            a => 0 ~ preserve(parameter)
            b(a) => a ~ accumulate
        end

        request = Dict(
            "observed" => Dict(
                "type" => "DataFrame",
                "columns" => [
                    Dict("name" => "time", "type" => "Float64"),
                    Dict("name" => "b", "type" => "Float64"),
                ],
                "rows" => [[10, 200]],
            ),
            "target" => "b",
            "stop" => 10,
            "parameters" => [
                Dict(
                    "system" => "SWebAPICalibration",
                    "name" => "a",
                    "lower" => 19.5,
                    "upper" => 20.5,
                ),
            ],
            "optim" => Dict(
                "MaxSteps" => 4,
                "TraceMode" => "silent",
            ),
        )

        response = Cropbox.calibrate_payload(SWebAPICalibration, request)
        @test response["status"] == "ok"
        @test response["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test response["operation"] == "calibrate"
        a = response["config"]["SWebAPICalibration"]["a"]["value"]
        @test 19.5 <= a <= 20.5
        @test response["summary"]["nparameters"] == 1

        nested_request = deepcopy(request)
        nested_request["parameters"] = Dict(
            "SWebAPICalibration" => Dict(
                "a" => Dict("lower" => 19.5, "upper" => 20.5),
            ),
        )
        nested_response = Cropbox.calibrate_payload(SWebAPICalibration, nested_request)
        @test nested_response["status"] == "ok"
        @test nested_response["operation"] == "calibrate"
        @test nested_response["summary"]["nparameters"] == 1

        csv_request = deepcopy(request)
        csv_request["observed"] = Dict(
            "type" => "CSV",
            "filename" => "observed_calibration.csv",
            "content" => "time,b\n10,200\n",
            "columns" => [
                Dict("name" => "time", "type" => "Float64"),
                Dict("name" => "b", "type" => "Float64"),
            ],
        )
        csv_response = Cropbox.calibrate_payload(SWebAPICalibration, csv_request)
        @test csv_response["status"] == "ok"
        @test csv_response["operation"] == "calibrate"
        @test csv_response["summary"]["nparameters"] == 1

        status, content_type, body = Cropbox.route_api_response(SWebAPICalibration, "POST", "/api/calibrate", JSON3.write(request))
        routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed["status"] == "ok"
        @test routed["operation"] == "calibrate"
    end

    @testset "simulate equivalence" begin
        request = Dict(
            "configs" => [
                Dict("SWebAPI" => Dict("a" => Dict("value" => 1, "unit" => "m"))),
                Dict("SWebAPI" => Dict("a" => Dict("value" => 3, "unit" => "m"))),
            ],
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "target" => ["a", "b"],
        )
        response = Cropbox.simulate_payload(SWebAPI, request)
        direct = simulate(
            SWebAPI;
            configs=[
                :SWebAPI => :a => 1u"m",
                :SWebAPI => :a => 3u"m",
            ],
            stop=1u"hr",
            target=[:a, :b],
            verbose=false,
        )
        assert_table_equivalent(response, direct)
    end

    @testset "simulate native keyword parity" begin
        @system SWebAPIOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::int(override)
        end

        options_request = Dict(
            "options" => Dict("a" => 1, "b" => 2),
            "stop" => 10,
            "target" => ["a", "b"],
        )
        options_normalized = Cropbox.normalize_request(SWebAPIOptions, options_request)
        @test options_normalized["options"] == (; a=1, b=2)
        options_response = Cropbox.simulate_payload(SWebAPIOptions, options_request)
        options_direct = simulate(
            SWebAPIOptions;
            options=(; a=1, b=2),
            stop=10,
            target=[:a, :b],
            verbose=false,
        )
        assert_table_equivalent(options_response, options_direct)

        @system SWebAPISeed(Controller) begin
            a => rand() ~ track
            b(a) ~ accumulate
        end

        seed_request = Dict(
            "seed" => 0,
            "stop" => 10,
            "target" => ["a", "b"],
        )
        seed_response_1 = Cropbox.simulate_payload(SWebAPISeed, seed_request)
        seed_response_2 = Cropbox.simulate_payload(SWebAPISeed, seed_request)
        seed_direct = simulate(
            SWebAPISeed;
            seed=0,
            stop=10,
            target=[:a, :b],
            verbose=false,
        )
        @test seed_response_1["rows"] == seed_response_2["rows"]
        assert_table_equivalent(seed_response_1, seed_direct)

        format_request = Dict(
            "config_entries" => Dict("SWebAPI.a" => Dict("value" => 2, "unit" => "m")),
            "stop" => Dict("value" => 2, "unit" => "hr"),
            "target" => ["a", "b"],
            "nounit" => true,
            "long" => true,
        )
        format_response = Cropbox.simulate_payload(SWebAPI, format_request)
        format_direct = simulate(
            SWebAPI;
            config=:SWebAPI => :a => 2u"m",
            stop=2u"hr",
            target=[:a, :b],
            nounit=true,
            long=true,
            verbose=false,
        )
        assert_table_equivalent(format_response, format_direct)
        @test "variable" in [c["name"] for c in format_response["columns"]]
        @test "value" in [c["name"] for c in format_response["columns"]]
    end

    @testset "simulate named target mappings" begin
        @system SWebAPIChild begin
            x => 3 ~ track
        end
        @system SWebAPINamedTargets(Controller) begin
            child(context) ~ ::SWebAPIChild
            y => 4 ~ track
        end

        request = Dict(
            "stop" => 1,
            "target" => [
                Dict("name" => "child_x", "path" => "child.x"),
                Dict("name" => "renamed_y", "path" => "y"),
            ],
        )
        normalized = Cropbox.normalize_request(SWebAPINamedTargets, request)
        @test normalized["target"] == [:child_x => "child.x", :renamed_y => :y]
        response = Cropbox.simulate_payload(SWebAPINamedTargets, request)
        direct = simulate(
            SWebAPINamedTargets;
            stop=1,
            target=[:child_x => "child.x", :renamed_y => :y],
            verbose=false,
        )
        assert_table_equivalent(response, direct)

        map_request = Dict(
            "stop" => 1,
            "target" => Dict("child_x" => "child.x", "renamed_y" => "y"),
        )
        map_response = Cropbox.simulate_payload(SWebAPINamedTargets, map_request)
        @test map_response["status"] == "ok"
        @test Set([c["name"] for c in map_response["columns"]]) == Set(names(direct))
        child_col = findfirst(c -> c["name"] == "child_x", map_response["columns"])
        y_col = findfirst(c -> c["name"] == "renamed_y", map_response["columns"])
        @test map_response["rows"][end][child_col] == 3
        @test map_response["rows"][end][y_col] == 4
    end

    @testset "date and datetime aliases over HTTP" begin
        @system SWebAPIDateTypes(Controller) begin
            naive => DateTime(2024, 1, 1) ~ preserve::DateTime(parameter)
            start => ZonedDateTime(2024, 1, 1, tz"Asia/Seoul") ~ preserve::datetime(parameter)
            day => Date(2024, 1, 1) ~ preserve::date(parameter)
            time(start) => start ~ track::datetime
        end
        types = [("naive", "DateTime"), ("start", "ZonedDateTime"), ("day", "Date")]
        server = serve(SWebAPIDateTypes; port=0, async=true)
        try
            url = api_server_url(server)
            model, model_response = http_get_json(url, "/api/model")
            @test model_response.status == 200
            for metadata in (describe(SWebAPIDateTypes), model), (name, kind) in types
                parameter = only(filter(p -> p["name"] == name, metadata["parameters"]))
                @test parameter["default"]["type"] == kind
            end
            widgets, widgets_response = http_get_json(url, "/api/dashboard")
            @test widgets_response.status == 200
            for (name, kind) in types
                control = only(filter(c -> c["name"] == name, widgets["controls"]))
                @test control["value_type"] == kind
            end
            time_output = only(filter(v -> v["target_path"] == "time", widgets["outputs"]))
            @test time_output["type"] == "ZonedDateTime"
            @test isnothing(time_output["unit"])

            request = Dict(
                "stop" => 0,
                "target" => ["time", "naive", "start", "day"],
                "config_entries" => Dict(
                    "SWebAPIDateTypes.naive" => Dict("type" => "DateTime", "value" => "2024-02-03T04:05:00"),
                    "SWebAPIDateTypes.start" => Dict("type" => "ZonedDateTime", "value" => "2024-02-03T04:05:00", "timezone" => "Asia/Seoul"),
                    "SWebAPIDateTypes.day" => Dict("type" => "Date", "value" => "2024-02-03"),
                ),
            )
            result, response = http_post_json(url, "/api/simulate", request)
            @test response.status == 200
            @test result["status"] == "ok"
            @test [c["type"] for c in result["columns"]] == ["ZonedDateTime", "DateTime", "ZonedDateTime", "Date"]
            @test only(result["rows"]) == ["2024-02-03T04:05:00+09:00", "2024-02-03T04:05:00", "2024-02-03T04:05:00+09:00", "2024-02-03"]
        finally
            close(server)
        end
    end

    @testset "widgets and visualize" begin
        widgets = Cropbox.widget_payload(SWebAPI)
        @test widgets["title"] == "SWebAPI Dashboard"
        @test widgets["contract"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test widgets["model"]["name"] == "SWebAPI"
        @test !haskey(widgets, "operations")
        @test any(c -> c["name"] == "a" &&
                       c["kind"] == "number" &&
                       c["declared_path"] == "SWebAPI.a" &&
                       isnothing(c["alias"]) &&
                       c["label"] == "a" &&
                       c["accepted_config_paths"] == ["SWebAPI.a"], widgets["controls"])
        clock_control = only(filter(c -> c["path"] == "Clock.step", widgets["controls"]))
        @test clock_control["source"] == "runtime"
        @test clock_control["default"] == 1
        @test clock_control["unit"] == "hr"
        @test first(widgets["visualize"]["x"]["options"]) == "time"
        @test widgets["visualize"]["x"]["default"] == "time"
        @test widgets["visualize"]["y"]["default"] == ["b"]
        @test !("a" in widgets["visualize"]["y"]["options"])
        configured_widgets = Cropbox.widget_payload(
            SWebAPI;
            config=(:Clock => :step => 0.5u"d",),
        )
        configured_clock = only(filter(c -> c["path"] == "Clock.step", configured_widgets["controls"]))
        @test configured_clock["default"] == 0.5
        @test configured_clock["unit"] == "d"
        configured_time = only(filter(v -> v["target_path"] == "time", configured_widgets["outputs"]))
        @test configured_time["unit"] == "hr"
        timed_result = Cropbox.simulate_payload(SWebAPI,
            Dict("stop" => 2, "target" => ["time"]); config=(:Clock => :step => 0.5u"d",))
        @test first(timed_result["columns"])["unit"] == configured_time["unit"]
        @test last(timed_result["rows"])[1] == 24
        @system SWebAPIDaily{Context => Cropbox.DailyContext}(Controller) begin
            y => 1 ~ track
        end
        daily_widgets = Cropbox.widget_payload(SWebAPIDaily)
        daily_clock = only(filter(c -> c["path"] == "Clock.step", daily_widgets["controls"]))
        @test daily_clock["system"] == "DailyClock"
        @test daily_clock["default"] == 1
        @test daily_clock["unit"] == "d"
        @test first(daily_widgets["outputs"])["unit"] == "d"
        @system SWebAPICalendarOutput(Controller) begin
            time => DateTime(2024, 1, 1) ~ preserve::DateTime
        end
        calendar_widgets = Cropbox.widget_payload(SWebAPICalendarOutput)
        @test first(calendar_widgets["outputs"])["declared_path"] == "SWebAPICalendarOutput.time"
        @test isnothing(first(calendar_widgets["outputs"])["unit"])
        calendar_result = Cropbox.simulate_payload(SWebAPICalendarOutput,
            Dict("stop" => 0, "target" => ["time"]))
        @test first(calendar_result["columns"])["type"] == "DateTime"
        @test first(calendar_result["rows"])[1] == "2024-01-01T00:00:00"
        @test widgets["visualize"]["kind"]["default"] == "line"
        @test widgets["visualize"]["kind"]["options"] == ["line", "scatter", "scatterline", "step"]
        @test widgets["simulation"]["stop"] == Dict("value" => 5, "unit" => "hr")
        @test isnothing(widgets["simulation"]["snap"])
        interval_widgets = Cropbox.widget_payload(
            SWebAPI;
            ui=Dict("snap" => Dict("value" => 2, "unit" => "hr")),
        )
        @test interval_widgets["simulation"]["snap"] == Dict("value" => 2, "unit" => "hr")
        @test !haskey(widgets, "evaluate")
        @test !haskey(widgets, "calibrate")
        @test !haskey(widgets, "manipulate")
        @test length(widgets["panels"]) == 1

        get_cache = Cropbox.api_get_route_cache(SWebAPI)
        @test !haskey(get_cache, "/api/widgets")
        @test JSON3.read(get_cache["/api/model"][3], Dict{String,Any})["model"]["name"] == "SWebAPI"
        @test JSON3.read(get_cache["/api/dashboard"][3], Dict{String,Any})["title"] == "SWebAPI Dashboard"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/", "")
        @test status == 200
        @test content_type == "text/html; charset=utf-8"
        @test occursin("aria-label=\"Run simulation\"", body)
        @test !occursin(">Run</button>", body)
        @test !occursin("Evaluation / calibration", body)
        @test !occursin("Observed CSV", body)
        @test !occursin("runEvaluation", body)
        @test !occursin("runCalibration", body)
        @test !occursin("addCalibrationBound", body)
        @test !occursin("calibration-bounds", body)
        @test occursin("aria-label=\"Add panel\"", body)
        @test !occursin("+ Bound", body)
        @test !occursin("Vary parameter", body)
        @test !occursin("Parameter sweep", body)
        @test occursin("/api/dashboard", body)
        @test occursin("aria-label=\"Download results as CSV\"", body)
        @test occursin("downloadTableCSV", body)
        @test !occursin("table-search", body)
        @test !occursin("table-status", body)
        @test !occursin("model-search", body)
        @test occursin("metadata-popover", body)
        @test occursin("id=\"layout-resizer\"", body)
        @test occursin("role=\"separator\"", body)
        @test occursin("initializeLayoutResizer", body)
        @test occursin("item.label !== item.alias", body)
        @test !occursin("Run to render", body)
        @test occursin("stop-mode", body)
        @test occursin("snap-mode", body)
        @test occursin("simulationRequestFields", body)
        @test !occursin("Request preview", body)
        @test occursin("<h2>Model</h2>", body)
        @test occursin("data-panel-y-option", body)
        @test occursin("Parameter / Table", body)
        @test occursin("Index (X axis)", body)
        @test occursin("Targets (Y axis)", body)
        @test occursin("Plot kind", body)
        @test !occursin("Y variables", body)
        @test occursin("config_entries", body)
        @test occursin("data-kind=\"parameter\"", body)
        @test occursin("data-role=\"table\"", body)
        @test occursin("data-path", body)
        @test occursin("postJSON(\"/api/simulate\"", body)
        @test occursin("postJSON(\"/api/visualize\"", body)
        @test !occursin("postJSON(\"/api/evaluate\"", body)
        @test !occursin("postJSON(\"/api/calibrate\"", body)
        @test occursin("run-button-spinner", body)
        @test occursin("aria-busy", body)
        @test occursin("panel-drop-indicator", body)
        @test occursin("data-panel-xmin", body)
        @test occursin("data-panel-ymin", body)
        @test occursin("position: sticky", body)
        @test occursin("overflow: auto", body)
        @test occursin("defaultValue === true ? \"checked\"", body)
        @test occursin("schema.outputs.map(outputPath)", body)
        @test occursin("panel.linestyles?.length === panel.y?.length", body)

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/dashboard", "")
        @test status == 200
        @test content_type == "text/html; charset=utf-8"
        @test occursin("Cropbox Dashboard", body)

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/", ""; dashboard=false)
        hidden_dashboard = JSON3.read(body, Dict{String,Any})
        @test status == 404
        @test content_type == "application/json; charset=utf-8"
        @test hidden_dashboard["error"]["category"] == "routing"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/dashboard", ""; dashboard=false)
        metadata_only = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test metadata_only["model"]["name"] == "SWebAPI"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/app", ""; dashboard="/app")
        @test status == 200
        @test content_type == "text/html; charset=utf-8"
        @test occursin("Cropbox Dashboard", body)

        ui = Dict(
            "title" => "Configured dashboard title",
            "stop" => Dict("value" => 14, "unit" => "d"),
            "panels" => [
                Dict("title" => "A", "x" => "time", "y" => ["a"], "kind" => "line", "linestyles" => ["dash"]),
                Dict("title" => "B", "x" => "time", "y" => ["b"], "kind" => "step"),
            ],
            "external_inputs" => [
                Dict("name" => "latitude", "label" => "Latitude", "default" => "35.8"),
                Dict("name" => "longitude", "label" => "Longitude", "default" => "127.1"),
            ],
            "external_sources" => [
                Dict(
                    "name" => "open-meteo",
                    "label" => "Open-Meteo daily weather",
                    "url" => "https://api.open-meteo.com/v1/forecast?latitude={latitude}&longitude={longitude}",
                    "target" => "SWebAPI.weather",
                    "time_path" => "daily.time",
                    "value_path" => "daily.temperature_2m_mean",
                ),
            ],
            "sweeps" => [
                Dict("label" => "SWebAPI.a", "system" => "SWebAPI", "name" => "a", "start" => 1, "stop" => 3, "step" => 1, "unit" => "m"),
            ],
        )
        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/dashboard", ""; ui)
        dashboard_schema = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test dashboard_schema["title"] == "Configured dashboard title"
        @test dashboard_schema["simulation"]["stop"]["value"] == 14
        @test dashboard_schema["simulation"]["stop"]["unit"] == "d"
        @test length(dashboard_schema["panels"]) == 2
        @test dashboard_schema["panels"][1]["linestyles"] == ["dash"]
        @test dashboard_schema["panels"][2]["kind"] == "step"
        @test length(dashboard_schema["sweeps"]) == 1
        @test dashboard_schema["sweeps"][1]["name"] == "a"
        @test dashboard_schema["external_inputs"][1]["name"] == "latitude"
        @test dashboard_schema["external_sources"][1]["name"] == "open-meteo"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/schema", "")
        schema = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test schema["title"] == "Cropbox Web API"
        @test schema["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test schema["contract"]["execution_model"] == "stateless-request"
        @test Set([e["category"] for e in schema["error_taxonomy"]]) == Set(["syntax", "validation", "execution", "routing"])
        @test !any(r -> r["path"] == "/api/validate", schema["routes"])
        @test any(r -> r["path"] == "/api/schema" && r["response"] == "JSONSchemaFragments", schema["routes"])
        @test !any(r -> r["path"] == "/api/widgets", schema["routes"])
        @test any(r -> r["path"] == "/api/simulate" && r["request"] == "SimulationRequest", schema["routes"])
        @test any(r -> r["path"] == "/api/evaluate" && r["request"] == "EvaluationRequest", schema["routes"])
        @test any(r -> r["path"] == "/api/calibrate" && r["request"] == "CalibrationRequest", schema["routes"])
        @test any(r -> r["path"] == "/api/openapi" && r["response"] == "OpenAPI", schema["routes"])
        @test any(r -> r["path"] == "/api/docs" && r["response"] == "SwaggerUI", schema["routes"])
        @test haskey(schema["definitions"], "ModelDescription")
        @test haskey(schema["definitions"], "VariableDescription")
        @test haskey(schema["definitions"], "ParameterDescription")
        @test haskey(schema["definitions"], "TableDescription")
        @test schema["definitions"]["TableDescription"]["properties"]["state"]["enum"] == ["provide"]
        @test haskey(schema["definitions"], "WidgetPayload")
        @test haskey(schema["definitions"], "ConfigEntry")
        @test haskey(schema["definitions"], "NameMapping")
        @test haskey(schema["definitions"], "NameSelection")
        @test haskey(schema["definitions"], "StepSelection")
        @test haskey(schema["definitions"], "SimulationResponse")
        @test haskey(schema["definitions"], "EvaluationResponse")
        @test haskey(schema["definitions"], "CalibrationResponse")
        @test haskey(schema["definitions"]["SimulationRequest"]["properties"], "config_entries")
        @test schema["definitions"]["SimulationRequest"]["properties"]["target"]["\$ref"] == "#/definitions/NameSelection"
        @test schema["definitions"]["SimulationRequest"]["properties"]["index"]["\$ref"] == "#/definitions/NameSelection"
        @test haskey(schema["definitions"]["SimulationRequest"]["properties"], "api_options")
        @test haskey(schema["definitions"]["SimulationRequest"]["properties"], "seed")
        @test haskey(schema["definitions"]["SimulationRequest"]["properties"], "nounit")
        @test haskey(schema["definitions"]["SimulationRequest"]["properties"], "long")
        @test "description" in schema["definitions"]["VariableDescription"]["required"]
        @test "unit" in schema["definitions"]["VariableDescription"]["required"]
        @test !("accepted_config_paths" in schema["definitions"]["VariableDescription"]["required"])
        @test "accepted_config_paths" in schema["definitions"]["ParameterDescription"]["required"]
        @test "description" in schema["definitions"]["TableDescription"]["required"]
        @test "role" in schema["definitions"]["TableDescription"]["required"]
        @test "source" in schema["definitions"]["WidgetControl"]["required"]
        @test schema["definitions"]["WidgetPayload"]["properties"]["controls"]["items"]["\$ref"] == "#/definitions/WidgetControl"
        visualize_properties = schema["definitions"]["VisualizationRequest"]["allOf"][2]["properties"]
        @test visualize_properties["xstep"]["\$ref"] == "#/definitions/StepSelection"
        @test !haskey(visualize_properties, "ystep")
        @test visualize_properties["plot"]["properties"]["linestyles"]["items"]["enum"] == ["solid", "dash", "dot", "dashdot"]
        @test haskey(schema["definitions"]["StepSelection"]["properties"], "values")
        @test haskey(schema["definitions"]["StepSelection"]["properties"], "unit")

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/openapi", "")
        openapi = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test openapi["openapi"] == "3.1.0"
        @test openapi["info"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test openapi["x-cropbox-contract"]["version"] == Cropbox.API_CONTRACT_VERSION
        @test haskey(openapi["paths"], "/api/simulate")
        @test haskey(openapi["paths"], "/api/evaluate")
        @test haskey(openapi["paths"], "/api/calibrate")
        @test haskey(openapi["paths"], "/api/docs")
        @test openapi["paths"]["/api/model"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]["\$ref"] == "#/components/schemas/ModelDescription"
        @test !haskey(openapi["paths"], "/api/widgets")
        @test openapi["paths"]["/api/dashboard"]["get"]["deprecated"] == false
        @test openapi["components"]["schemas"]["WidgetControl"]["properties"]["source"]["enum"] == ["dsl", "runtime"]
        @test openapi["paths"]["/api/simulate"]["post"]["requestBody"]["content"]["application/json"]["schema"]["\$ref"] == "#/components/schemas/SimulationRequest"
        @test openapi["paths"]["/api/evaluate"]["post"]["responses"]["200"]["content"]["application/json"]["schema"]["\$ref"] == "#/components/schemas/EvaluationResponse"
        @test haskey(openapi["paths"]["/api/model"]["get"]["responses"]["200"]["content"]["application/json"], "examples")
        @test haskey(openapi["paths"]["/api/simulate"]["post"]["requestBody"]["content"]["application/json"], "examples")
        @test openapi["paths"]["/api/docs"]["get"]["responses"]["200"]["content"]["text/html"]["schema"]["type"] == "string"
        @test openapi["components"]["schemas"]["SimulationResponse"]["properties"]["columns"]["items"]["\$ref"] == "#/components/schemas/Column"
        @test haskey(openapi["components"]["schemas"], "ConfigEntry")
        @test haskey(openapi["components"]["schemas"], "CalibrationRequest")
        @test haskey(openapi["components"]["schemas"], "StepSelection")
        openapi_visualize_properties = openapi["components"]["schemas"]["VisualizationRequest"]["allOf"][2]["properties"]
        @test openapi_visualize_properties["xstep"]["\$ref"] == "#/components/schemas/StepSelection"
        @test !haskey(openapi_visualize_properties, "ystep")

        request = Dict(
            "config_entries" => [
                Dict("path" => "SWebAPI.a", "value" => Dict("value" => 2, "unit" => "m")),
            ],
            "stop" => Dict("value" => 2, "unit" => "hr"),
            "x" => "time",
            "y" => "b",
        )
        response = Cropbox.visualize_payload(SWebAPI, request)
        @test response["status"] == "ok"
        @test response["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test response["format"] == "svg"
        @test occursin("<svg", response["body"])

        styled_request = merge(
            request,
            Dict(
                "y" => ["a", "b"],
                "plot" => Dict("linestyles" => ["solid", "dash"]),
            ),
        )
        styled_response = Cropbox.visualize_payload(SWebAPI, styled_request)
        @test styled_response["status"] == "ok"
        @test occursin("stroke-dasharray", styled_response["body"])

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "POST", "/api/visualize", JSON3.write(request))
        routed = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed["status"] == "ok"
        @test routed["content_type"] == "image/svg+xml"
    end

    @testset "lotka-volterra API equivalence" begin
        @system SWebAPILotkaVolterra(Controller) begin
            t(context.clock.time) ~ track(u"yr")
            N(N, P, b, a): prey_population => b*N - a*N*P ~ accumulate(init=N0)
            P(N, P, c, a, m): predator_population => c*a*N*P - m*P ~ accumulate(init=P0)
            N0: prey_initial_population ~ preserve(parameter)
            P0: predator_initial_population ~ preserve(parameter)
            b: prey_birth_rate ~ preserve(u"yr^-1", parameter)
            a: predation_rate ~ preserve(u"yr^-1", parameter)
            c: predator_reproduction_rate ~ preserve(parameter)
            m: predator_mortality_rate ~ preserve(u"yr^-1", parameter)
        end

        api_config = Dict(
            "Clock" => Dict("step" => Dict("value" => 1, "unit" => "d")),
            "SWebAPILotkaVolterra" => Dict(
                "b" => 0.6,
                "a" => 0.02,
                "c" => 0.5,
                "m" => Dict("value" => 0.5, "unit" => "yr^-1"),
                "N0" => 20,
                "P0" => 30,
            ),
        )
        request = Dict(
            "config" => api_config,
            "stop" => Dict("value" => 20, "unit" => "yr"),
            "target" => ["t", "N", "P"],
        )
        response = Cropbox.simulate_payload(SWebAPILotkaVolterra, request)
        direct = simulate(
            SWebAPILotkaVolterra;
            config=@config(
                :Clock => :step => 1u"d",
                :SWebAPILotkaVolterra => (;
                    b = 0.6,
                    a = 0.02,
                    c = 0.5,
                    m = 0.5u"yr^-1",
                    N0 = 20,
                    P0 = 30,
                ),
            ),
            stop=20u"yr",
            target=[:t, :N, :P],
            verbose=false,
        )
        assert_table_equivalent(response, direct)
        @test response["columns"][2]["name"] == "t"
        @test response["columns"][2]["unit"] == "yr"

        plot = Cropbox.visualize_payload(
            SWebAPILotkaVolterra,
            Dict(
                "config" => api_config,
                "stop" => Dict("value" => 1, "unit" => "yr"),
                "x" => "t",
                "y" => ["N", "P"],
                "kind" => "line",
            ),
        )
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
    end

    @testset "pheno configs API route equivalence" begin
        t0 = ZonedDateTime(2016, 9, 1, tz"UTC")
        t1 = ZonedDateTime(2018, 9, 30, tz"UTC")
        weather = DataFrame(index=collect(t0:Dates.Hour(1):t1), tavg=25.0)
        pheno_config = (
            :Estimator => (
                :tz => tz"UTC",
                :store => weather,
            ),
            :BetaFuncEstimator => (
                :To => 20,
                :Tx => 35,
                :Rg => 1000,
            ),
        )
        request = Dict(
            "configs" => [
                Dict("BetaFuncEstimator" => Dict("year" => 2017)),
                Dict("BetaFuncEstimator" => Dict("year" => 2018)),
            ],
            "index" => ["year", "calendar.time"],
            "target" => ["ΔT", "Cg", "match", "stop"],
            "stop" => "stop",
            "snap" => "match",
        )

        status, content_type, body = Cropbox.route_api_response(
            WebAPIPheno.BetaFuncEstimator,
            "GET",
            "/api/model",
            "";
            config=pheno_config,
        )
        model = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test any(p -> p["name"] == "Rg" &&
                       p["alias"] == "growth_requirement" &&
                       p["config_path"] == "BetaFuncEstimator.Rg", model["parameters"])
        @test any(t -> t["name"] == "s" &&
                       t["role"] == "table" &&
                       any(c -> c["name"] == "T" && c["column"] == "tavg", t["consumers"]), model["tables"])

        status, content_type, body = Cropbox.route_api_response(
            WebAPIPheno.BetaFuncEstimator,
            "POST",
            "/api/simulate",
            JSON3.write(request);
            config=pheno_config,
        )
        routed = JSON3.read(body, Dict{String,Any})
        direct = WebAPIPheno.estimate(
            WebAPIPheno.BetaFuncEstimator,
            [2017, 2018];
            config=pheno_config,
            target=[:ΔT, :Cg, :match, :stop],
            verbose=false,
        )
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        assert_table_equivalent(routed, direct; atol=1e-6)
        @test routed["summary"]["nrow"] == 2
        @test all(row -> row[5] == true && row[6] == true, routed["rows"])
        @test all(row -> row[4] >= 1000, routed["rows"])

        visualize_request = Dict(
            "config_entries" => [
                Dict("path" => "BetaFuncEstimator.year", "value" => 2017),
            ],
            "x" => "calendar.time",
            "y" => "Cg",
            "stop" => "stop",
            "snap" => "match",
            "kind" => "line",
        )
        status, content_type, body = Cropbox.route_api_response(
            WebAPIPheno.BetaFuncEstimator,
            "POST",
            "/api/visualize",
            JSON3.write(visualize_request);
            config=pheno_config,
        )
        plot = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
    end

    if WEBAPI_HAS_SIMPLECROP
    @testset "SimpleCrop CSV API route equivalence" begin
        weather_csv = read(joinpath(@__DIR__, "../examples/data/simplecrop/weather.csv"), String)
        irrigation_csv = read(joinpath(@__DIR__, "../examples/data/simplecrop/irrigation.csv"), String)
        api_config = Dict(
            "Clock" => Dict("step" => Dict("value" => 1, "unit" => "d")),
            "Calendar" => Dict(
                "init" => Dict(
                    "value" => "1987-01-01T00:00:00",
                    "type" => "ZonedDateTime",
                    "timezone" => "UTC",
                ),
            ),
            "Weather" => Dict(
                "weather_data" => Dict(
                    "type" => "CSV",
                    "filename" => "weather.csv",
                    "content" => weather_csv,
                ),
            ),
            "SoilWater" => Dict(
                "irrigation_data" => Dict(
                    "type" => "CSV",
                    "filename" => "irrigation.csv",
                    "content" => irrigation_csv,
                ),
            ),
        )
        request = Dict(
            "config" => api_config,
            "stop" => "endsim",
            "target" => ["DATE", "LAI"],
        )
        status, content_type, body = Cropbox.route_api_response(
            SimpleCrop.Model,
            "POST",
            "/api/simulate",
            JSON3.write(request),
        )
        routed = JSON3.read(body, Dict{String,Any})
        direct = simulate(
            SimpleCrop.Model;
            config=@config(
                :Clock => :step => 1u"d",
                :Calendar => :init => ZonedDateTime(1987, 1, 1, tz"UTC"),
                :Weather => :weather_data => DataFrame(CSV.File(joinpath(@__DIR__, "../examples/data/simplecrop/weather.csv"))),
                :SoilWater => :irrigation_data => DataFrame(CSV.File(joinpath(@__DIR__, "../examples/data/simplecrop/irrigation.csv"))),
            ),
            stop=:endsim,
            target=[:DATE, :LAI],
            verbose=false,
        )
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        assert_table_equivalent(routed, direct; atol=1e-6)
        @test routed["summary"]["nrow"] == 294
        @test routed["rows"][1][2] == "1987-01-01"
        @test routed["rows"][end][2] == "1987-10-21"
        @test routed["rows"][end][3] > 0.9

        visualize_request = Dict(
            "config" => api_config,
            "stop" => "endsim",
            "x" => "DATE",
            "y" => "LAI",
            "kind" => "line",
        )
        status, content_type, body = Cropbox.route_api_response(
            SimpleCrop.Model,
            "POST",
            "/api/visualize",
            JSON3.write(visualize_request),
        )
        plot = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
    end
    else
        @info "Skipping SimpleCrop Web API integration tests; package is not available in the active environment"
    end

    @testset "table payload values" begin
        nonfinite = Cropbox.table_payload(DataFrame(a=[1.0, NaN, Inf]); model="SWebAPI")
        @test nonfinite["rows"] == [[1.0], [nothing], [nothing]]
        @test JSON3.read(JSON3.write(nonfinite), Dict{String,Any})["rows"][2][1] === nothing

        request = Dict(
            "config" => Dict(
                "SWebAPI" => Dict(
                    "weather" => Dict(
                        "type" => "CSV",
                        "filename" => "weather.csv",
                        "content" => "time,tavg\n2024-02-01T00:00:00,6.2\n",
                        "columns" => [
                            Dict("name" => "time", "type" => "ZonedDateTime", "timezone" => "Asia/Seoul"),
                            Dict("name" => "tavg", "type" => "Float64", "unit" => "K"),
                        ],
                    ),
                ),
            ),
        )
        normalized = Cropbox.normalize_request(SWebAPI, request)
        weather = normalized["config"][:SWebAPI][:weather]
        @test nrow(weather) == 1
        @test weather.time[1] isa TimeZones.ZonedDateTime
        @test weather.tavg[1] == 6.2u"K"

        offset_request = Dict(
            "config_entries" => [
                Dict(
                    "path" => "SWebAPI.weather",
                    "value" => Dict(
                        "type" => "CSV",
                        "filename" => "offset-weather.csv",
                        "content" => "time,tavg\n2024-07-01T00:00:00.000+09:00,7.5\n",
                        "columns" => [
                            Dict("name" => "time", "type" => "ZonedDateTime", "timezone" => "Asia/Seoul"),
                            Dict("name" => "tavg", "type" => "Float64", "unit" => "K"),
                        ],
                    ),
                ),
            ],
        )
        offset_normalized = Cropbox.normalize_request(SWebAPI, offset_request)
        offset_weather = offset_normalized["config"][:SWebAPI][:weather]
        @test offset_weather.time[1] == ZonedDateTime(2024, 7, 1, tz"Asia/Seoul")
        @test timezone(offset_weather.time[1]) == tz"Asia/Seoul"

        legacy_csv = Dict(
            "type" => "CSV",
            "content" => "\"date (:Date)\",\"temperature (°C)\"\n2024-02-01,6.2\n",
        )
        legacy = Cropbox.parse_api_value(legacy_csv)
        @test names(legacy) == ["date", "temperature"]
        @test legacy.date == [Date(2024, 2, 1)]
        @test legacy.temperature == [6.2u"°C"]

        unsafe_csv = Dict(
            "type" => "CSV",
            "content" => "\"value (:DefinitelyNotAType)\",other\n1,2\n",
        )
        @test_throws Cropbox.APIRequestError Cropbox.parse_api_value(unsafe_csv)
        unsafe_table = Dict(
            "type" => "DataFrame",
            "columns" => [Dict("name" => "value (:DefinitelyNotAType)")],
            "rows" => [[1]],
        )
        @test_throws Cropbox.APIRequestError Cropbox.parse_api_value(unsafe_table)
        @test_throws Cropbox.APIRequestError Cropbox.parse_api_unit("Base.eval")
        status, _, body = Cropbox.route_api_response(
            SWebAPI,
            "POST",
            "/api/simulate",
            JSON3.write(Dict(
                "config" => Dict("SWebAPI" => Dict("weather" => unsafe_csv)),
                "stop" => 1,
                "target" => "b",
            )),
        )
        rejected = JSON3.read(body, Dict{String,Any})
        @test status == 422
        @test rejected["error"]["category"] == "validation"
        @test !occursin("eval", lowercase(rejected["error"]["message"]))
    end

    @testset "dashboard table input schema" begin
        @system SWebAPITableInput{Context => Cropbox.DailyContext}(Controller) begin
            weather ~ provide(parameter)
            T: temperature ~ drive(from=weather, by=:tavg, u"°C")
        end

        widgets = Cropbox.widget_payload(SWebAPITableInput)
        weather = only(filter(c -> c["name"] == "weather", widgets["controls"]))
        @test weather["role"] == "table"
        @test weather["kind"] == "file"
        @test weather["accept"] == ".csv,text/csv"
        @test only(weather["columns"])["column"] == "tavg"
        @test any(v -> v["name"] == "T", widgets["outputs"])

        table_columns = [
            Dict("name" => "index", "type" => "ZonedDateTime", "timezone" => "Asia/Seoul"),
            Dict("name" => "tavg", "type" => "Float64", "unit" => "°C"),
        ]
        configured_widgets = Cropbox.widget_payload(
            SWebAPITableInput;
            ui=Dict(
                "table_inputs" => [
                    Dict(
                        "path" => "SWebAPITableInput.weather",
                        "label" => "Hourly weather",
                        "default_filename" => "weather.csv",
                        "columns" => table_columns,
                    ),
                ],
            ),
        )
        configured_weather = only(filter(c -> c["name"] == "weather", configured_widgets["controls"]))
        @test configured_weather["label"] == "Hourly weather"
        @test configured_weather["default_filename"] == "weather.csv"
        @test configured_weather["columns"] == table_columns

        description = Cropbox.describe(SWebAPITableInput)
        table = only(filter(t -> t["name"] == "weather", description["tables"]))
        @test table["config_path"] == "SWebAPITableInput.weather"
        @test table["state"] == "provide"
        @test table["index"] == "index"
        @test table["consumers"][1]["name"] == "T"
        @test table["consumers"][1]["column"] == "tavg"
        @test table["consumers"][1]["unit"] == "°C"
    end

    @testset "route errors" begin
        status, content_type, body = Cropbox.route_api_response(SWebAPI, "GET", "/api/missing", "")
        missing = JSON3.read(body, Dict{String,Any})
        @test status == 404
        @test content_type == "application/json; charset=utf-8"
        @test missing["status"] == "error"
        @test missing["contract_version"] == Cropbox.API_CONTRACT_VERSION
        @test missing["error"]["code"] == "not_found"
        @test missing["error"]["category"] == "routing"
        @test missing["error"]["path"] == "/api/missing"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "POST", "/api/simulate", "{")
        invalid = JSON3.read(body, Dict{String,Any})
        @test status == 400
        @test content_type == "application/json; charset=utf-8"
        @test invalid["status"] == "error"
        @test invalid["error"]["code"] == "invalid_request"
        @test invalid["error"]["category"] == "syntax"
        @test invalid["error"]["path"] == "/api/simulate"

        status, content_type, body = Cropbox.route_api_response(SWebAPI, "POST", "/api/evaluate", "{}")
        validation = JSON3.read(body, Dict{String,Any})
        @test status == 422
        @test content_type == "application/json; charset=utf-8"
        @test validation["status"] == "error"
        @test validation["error"]["code"] == "invalid_request"
        @test validation["error"]["category"] == "validation"
        @test validation["error"]["retryable"] == false

        @system SWebAPIExecutionFailure(Controller) begin
            failed => error("model execution failed") ~ track
        end
        status, content_type, body = Cropbox.route_api_response(
            SWebAPIExecutionFailure,
            "POST",
            "/api/simulate",
            JSON3.write(Dict("stop" => Dict("value" => 1, "unit" => "hr"), "target" => ["failed"])),
        )
        execution = JSON3.read(body, Dict{String,Any})
        @test status == 500
        @test content_type == "application/json; charset=utf-8"
        @test execution["error"]["code"] == "execution_failed"
        @test execution["error"]["category"] == "execution"
        @test execution["error"]["path"] == "/api/simulate"

        status, _, body = Cropbox.route_api_response(
            SWebAPI,
            "POST",
            "/api/simulate",
            JSON3.write(Dict("stop" => "not_a_variable", "target" => "b")),
        )
        unknown = JSON3.read(body, Dict{String,Any})
        @test status == 422
        @test unknown["error"]["category"] == "validation"
        @test unknown["error"]["message"] == "Request references an unknown model variable or path."
    end

    @testset "GDD phenology API example" begin
        @system SWebAPIGDD(GrowingDegree, Controller) begin
            weather ~ provide(parameter)
            T: temperature ~ drive(from=weather, by=:tavg, u"°C")
            daily_gdd(T, Tb) => max(T - Tb, 0u"K") ~ track(u"K")
            TT(daily_gdd): thermal_time => daily_gdd ~ accumulate(u"K*d")
            phyllochron => 50 ~ preserve(u"K*d", parameter)
            leaves(TT, phyllochron): leaf_number => TT / phyllochron ~ track
        end

        external_source = Dict(
            "name" => "open-meteo",
            "target" => "SWebAPIGDD.weather",
            "time_path" => "daily.time",
            "value_path" => "daily.temperature_2m_mean",
            "columns" => [
                Dict("name" => "index", "type" => "Float64", "unit" => "d"),
                Dict("name" => "tavg", "type" => "Float64", "unit" => "°C"),
            ],
        )
        external_response = Dict(
            "daily" => Dict(
                "time" => ["2026-04-01", "2026-04-02", "2026-04-03", "2026-04-04", "2026-04-05"],
                "temperature_2m_mean" => [12, 14, 18, 21, 25],
            ),
        )
        weather_payload = Cropbox.external_table_payload(external_source, external_response)
        @test weather_payload["type"] == "CSV"
        @test weather_payload["source"]["target"] == "SWebAPIGDD.weather"
        @test weather_payload["summary"]["nrow"] == 5
        @test weather_payload["content"] == "index,tavg\n0,12\n1,14\n2,18\n3,21\n4,25\n"

        api_config = Dict(
            "Clock" => Dict("step" => Dict("value" => 1, "unit" => "d")),
            "SWebAPIGDD" => Dict(
                "weather" => weather_payload,
                "Tb" => Dict("value" => 10, "unit" => "°C"),
                "phyllochron" => Dict("value" => 50, "unit" => "K*d"),
            ),
        )
        request = Dict(
            "config" => api_config,
            "stop" => Dict("value" => 4, "unit" => "d"),
            "target" => ["T", "ΔT", "TT", "leaves"],
        )

        response = Cropbox.simulate_payload(SWebAPIGDD, request)
        direct = simulate(
            SWebAPIGDD;
            config=@config(
                :Clock => :step => 1u"d",
                :SWebAPIGDD => (;
                    weather = DataFrame(index=(0:4)u"d", tavg=[12, 14, 18, 21, 25]u"°C"),
                    Tb = 10u"°C",
                    phyllochron = 50u"K*d",
                ),
            ),
            stop=4u"d",
            target=[:T, :ΔT, :TT, :leaves],
            verbose=false,
        )
        @test response["status"] == "ok"
        assert_table_equivalent(response, direct)
        @test response["columns"][2]["name"] == "T"
        @test response["columns"][2]["unit"] == "°C"
        @test response["rows"][end][4] == Cropbox.deunitfy(direct.TT[end])
        @test response["rows"][end][5] == Cropbox.deunitfy(direct.leaves[end])
        @test response["rows"][end][5] > 0.0

        plot = Cropbox.visualize_payload(
            SWebAPIGDD,
            Dict(
                "config" => api_config,
                "stop" => Dict("value" => 4, "unit" => "d"),
                "x" => "time",
                "y" => "TT",
            ),
        )
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
        @test occursin("K*d", plot["body"])

        observed = Dict(
            "type" => "DataFrame",
            "columns" => [
                Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                Dict("name" => "leaves", "type" => "Float64"),
            ],
            "rows" => [
                [response["rows"][3][1], response["rows"][3][5]],
                [response["rows"][end][1], response["rows"][end][5]],
            ],
        )
        evaluation = Cropbox.evaluate_payload(
            SWebAPIGDD,
            Dict(
                "config" => api_config,
                "observed" => observed,
                "target" => "leaves",
                "stop" => Dict("value" => 4, "unit" => "d"),
                "metric" => "rmse",
            ),
        )
        @test evaluation["status"] == "ok"
        @test evaluation["operation"] == "evaluate"
        @test evaluation["value"]["value"] < 1e-8

        gdd_evaluate_request = Dict(
            "config" => api_config,
            "observed" => observed,
            "target" => "leaves",
            "stop" => Dict("value" => 4, "unit" => "d"),
            "metric" => "rmse",
        )
        status, content_type, body = Cropbox.route_api_response(
            SWebAPIGDD,
            "POST",
            "/api/evaluate",
            JSON3.write(gdd_evaluate_request),
        )
        routed_evaluation = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_evaluation["operation"] == "evaluate"
        @test routed_evaluation["value"]["value"] < 1e-8

        gdd_calibrate_request = Dict(
            "config" => api_config,
            "observed" => observed,
            "target" => "leaves",
            "stop" => Dict("value" => 4, "unit" => "d"),
            "metric" => "rmse",
            "parameters" => [
                Dict(
                    "system" => "SWebAPIGDD",
                    "name" => "phyllochron",
                    "lower" => 45,
                    "upper" => 55,
                    "unit" => "K*d",
                ),
            ],
            "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent"),
        )
        calibration = Cropbox.calibrate_payload(SWebAPIGDD, gdd_calibrate_request)
        @test calibration["status"] == "ok"
        @test calibration["operation"] == "calibrate"
        fitted = calibration["config"]["SWebAPIGDD"]["phyllochron"]["value"]
        @test 45 <= fitted <= 55

        status, content_type, body = Cropbox.route_api_response(
            SWebAPIGDD,
            "POST",
            "/api/calibrate",
            JSON3.write(gdd_calibrate_request),
        )
        routed_calibration = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_calibration["operation"] == "calibrate"
        routed_fitted = routed_calibration["config"]["SWebAPIGDD"]["phyllochron"]["value"]
        @test 45 <= routed_fitted <= 55

        closed_config = merge_api_config(api_config, routed_calibration["config"])
        closed_evaluation = Cropbox.evaluate_payload(
            SWebAPIGDD,
            Dict(
                "config" => closed_config,
                "observed" => observed,
                "target" => "leaves",
                "stop" => Dict("value" => 4, "unit" => "d"),
                "metric" => "rmse",
            ),
        )
        @test closed_evaluation["status"] == "ok"
        @test closed_evaluation["summary"]["nobs"] == 2
        @test isfinite(closed_evaluation["value"]["value"])
    end

    @testset "chilling-forcing phenology API example" begin
        @system SWebAPICF(Controller) begin
            weather ~ provide(parameter)
            T: temperature ~ drive(from=weather, by=:tavg, u"°C")
            Tc_min => 0 ~ preserve(u"°C", parameter)
            Tc_max => 7.2 ~ preserve(u"°C", parameter)
            Tf => 4 ~ preserve(u"°C", parameter)
            chill_requirement => 2 ~ preserve(u"d", parameter)
            forcing_requirement => 12 ~ preserve(u"K*d", parameter)
            chill_rate(T, Tc_min, Tc_max) => ifelse(Tc_min <= T && T <= Tc_max, 1, 0) ~ track
            chill(chill_rate) => chill_rate ~ accumulate(u"d")
            chill_progress(chill, chill_requirement) => min(chill / chill_requirement, 1) ~ track
            forcing_rate(T, Tf, chill_progress) => ifelse(chill_progress >= 1, max(T - Tf, 0u"K"), 0u"K") ~ track(u"K")
            forcing(forcing_rate) => forcing_rate ~ accumulate(u"K*d")
            bloom_progress(forcing, forcing_requirement) => min(forcing / forcing_requirement, 1) ~ track
            bloom_index(bloom_progress) => ifelse(bloom_progress >= 1, 1, 0) ~ track
        end

        weather_csv = """
        index,tavg
        0,4
        1,5
        2,6
        3,10
        4,12
        5,14
        """
        api_config = Dict(
            "Clock" => Dict("step" => Dict("value" => 1, "unit" => "d")),
            "SWebAPICF" => Dict(
                "weather" => Dict(
                    "type" => "CSV",
                    "filename" => "cf_weather.csv",
                    "content" => weather_csv,
                    "columns" => [
                        Dict("name" => "index", "type" => "Float64", "unit" => "d"),
                        Dict("name" => "tavg", "type" => "Float64", "unit" => "°C"),
                    ],
                ),
                "chill_requirement" => Dict("value" => 2, "unit" => "d"),
                "forcing_requirement" => Dict("value" => 12, "unit" => "K*d"),
            ),
        )
        request = Dict(
            "config" => api_config,
            "stop" => Dict("value" => 5, "unit" => "d"),
            "target" => ["T", "chill", "chill_progress", "forcing", "bloom_progress", "bloom_index"],
        )

        response = Cropbox.simulate_payload(SWebAPICF, request)
        @test response["status"] == "ok"
        @test response["summary"]["nrow"] == 6
        @test response["rows"][end][4] == 1.0
        @test response["rows"][end][6] == 1.0
        @test response["rows"][end][7] == 1.0

        progress = Cropbox.visualize_payload(
            SWebAPICF,
            Dict(
                "config" => api_config,
                "stop" => Dict("value" => 5, "unit" => "d"),
                "x" => "time",
                "y" => ["chill_progress", "bloom_progress"],
                "kind" => "line",
            ),
        )
        @test progress["status"] == "ok"
        @test occursin("<svg", progress["body"])

        forcing = Cropbox.visualize_payload(
            SWebAPICF,
            Dict(
                "config" => api_config,
                "stop" => Dict("value" => 5, "unit" => "d"),
                "x" => "time",
                "y" => "forcing",
                "kind" => "line",
            ),
        )
        @test forcing["status"] == "ok"
        @test occursin("<svg", forcing["body"])
        @test occursin("K*d", forcing["body"])

        observed = Dict(
            "type" => "DataFrame",
            "columns" => [
                Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                Dict("name" => "bloom_progress", "type" => "Float64"),
            ],
            "rows" => [
                [response["rows"][4][1], response["rows"][4][6]],
                [response["rows"][5][1], response["rows"][5][6]],
                [response["rows"][end][1], response["rows"][end][6]],
            ],
        )

        evaluation = Cropbox.evaluate_payload(
            SWebAPICF,
            Dict(
                "config" => api_config,
                "observed" => observed,
                "target" => "bloom_progress",
                "stop" => Dict("value" => 5, "unit" => "d"),
                "metric" => "rmse",
            ),
        )
        @test evaluation["status"] == "ok"
        @test evaluation["operation"] == "evaluate"
        @test evaluation["value"]["value"] < 1e-8

        cf_evaluate_request = Dict(
            "config" => api_config,
            "observed" => observed,
            "target" => "bloom_progress",
            "stop" => Dict("value" => 5, "unit" => "d"),
            "metric" => "rmse",
        )
        status, content_type, body = Cropbox.route_api_response(
            SWebAPICF,
            "POST",
            "/api/evaluate",
            JSON3.write(cf_evaluate_request),
        )
        routed_evaluation = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_evaluation["operation"] == "evaluate"
        @test routed_evaluation["value"]["value"] < 1e-8

        cf_calibrate_request = Dict(
            "config" => api_config,
            "observed" => observed,
            "target" => "bloom_progress",
            "stop" => Dict("value" => 5, "unit" => "d"),
            "metric" => "rmse",
            "parameters" => [
                Dict(
                    "system" => "SWebAPICF",
                    "name" => "forcing_requirement",
                    "lower" => 10,
                    "upper" => 14,
                    "unit" => "K*d",
                ),
            ],
            "optim" => Dict("MaxSteps" => 4, "TraceMode" => "silent"),
        )
        calibration = Cropbox.calibrate_payload(SWebAPICF, cf_calibrate_request)
        @test calibration["status"] == "ok"
        @test calibration["operation"] == "calibrate"
        fitted = calibration["config"]["SWebAPICF"]["forcing_requirement"]["value"]
        @test 10 <= fitted <= 14

        status, content_type, body = Cropbox.route_api_response(
            SWebAPICF,
            "POST",
            "/api/calibrate",
            JSON3.write(cf_calibrate_request),
        )
        routed_calibration = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_calibration["operation"] == "calibrate"
        routed_fitted = routed_calibration["config"]["SWebAPICF"]["forcing_requirement"]["value"]
        @test 10 <= routed_fitted <= 14

        closed_config = merge_api_config(api_config, routed_calibration["config"])
        closed_evaluation = Cropbox.evaluate_payload(
            SWebAPICF,
            Dict(
                "config" => closed_config,
                "observed" => observed,
                "target" => "bloom_progress",
                "stop" => Dict("value" => 5, "unit" => "d"),
                "metric" => "rmse",
            ),
        )
        @test closed_evaluation["status"] == "ok"
        @test closed_evaluation["summary"]["nobs"] == 3
        @test isfinite(closed_evaluation["value"]["value"])
    end

    if WEBAPI_HAS_LEAFGASEXCHANGE
    @testset "LeafGasExchange nested API example" begin
        gas_config = Dict(
            "Weather" => Dict(
                "PFD" => 300,
                "CO2" => 400,
                "RH" => 60,
                "T_air" => 4.5,
                "wind" => 2.0,
            ),
            "Nitrogen" => Dict(
                "_a" => 0.0004,
                "_b" => 0.0120,
                "_c" => 0,
                "SPAD" => 60,
            ),
            "StomataTuzet" => Dict(
                "sf" => 2.3,
                "Ψf" => -1.2,
            ),
            "ModelC3MD" => Dict(
                "Vcm25" => 14.0,
                "Jm25" => 20.0,
            ),
            "C3p" => Dict(
                "Tp25" => 2.8,
            ),
        )
        gas_config_julia = (
            :Weather => (
                PFD = 300,
                CO2 = 400,
                RH = 60,
                T_air = 4.5,
                wind = 2.0,
            ),
            :Nitrogen => (
                _a = 0.0004,
                _b = 0.0120,
                _c = 0,
                SPAD = 60,
            ),
            :StomataTuzet => (
                sf = 2.3,
                Ψf = -1.2,
            ),
            :ModelC3MD => (
                Vcm25 = 14.0,
                Jm25 = 20.0,
            ),
            :C3p => (
                Tp25 = 2.8,
            ),
        )

        gas_model = Cropbox.describe(LeafGasExchange.ModelC3MD; config=gas_config_julia)
        @test any(p -> p["name"] == "CO2" &&
                       p["declared_path"] == "Weather.CO2" &&
                       p["config_path"] == "ModelC3MD.CO2" &&
                       "Weather.CO2" in p["accepted_config_paths"], gas_model["parameters"])
        gas_widgets = Cropbox.widget_payload(LeafGasExchange.ModelC3MD; config=gas_config_julia)
        @test any(c -> c["path"] == "ModelC3MD.CO2" &&
                       "Weather.CO2" in c["accepted_config_paths"], gas_widgets["controls"])
        nitrogen_a = only(filter(
            c -> c["path"] == "ModelC3MD.__Nitrogen__a",
            gas_widgets["controls"],
        ))
        @test nitrogen_a["path"] == "ModelC3MD.__Nitrogen__a"
        @test nitrogen_a["declared_path"] == "Nitrogen._a"
        @test nitrogen_a["alias"] == "SPAD_N_coeff_a"
        @test nitrogen_a["label"] == "_a"
        @test any(p -> p["name"] == "Tp25" &&
                       p["declared_path"] == "C3p.Tp25" &&
                       "C3p.Tp25" in p["accepted_config_paths"], gas_model["parameters"])
        @test any(v -> v["name"] == "A_net" && v["target_path"] == "A_net", gas_model["variables"])
        @test only(v["type"] for v in gas_model["variables"] if v["name"] == "A_net") == "Float64"

        response = Cropbox.simulate_payload(
            LeafGasExchange.ModelC3MD,
            Dict(
                "config" => gas_config,
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "target" => ["A_net", "Ac", "Aj", "Ap", "Ci"],
            ),
        )
        @test response["status"] == "ok"
        @test response["summary"]["nrow"] >= 2
        @test response["rows"][end][2] > 1.5

        aci_plot = Cropbox.visualize_payload(
            LeafGasExchange.ModelC3MD,
            Dict(
                "config" => gas_config,
                "x" => "Ci",
                "y" => ["A_net", "Ac", "Aj", "Ap"],
                "xstep" => Dict(
                    "system" => "Weather",
                    "name" => "CO2",
                    "start" => 330,
                    "stop" => 470,
                    "step" => 20,
                ),
                "kind" => "line",
            ),
        )
        @test aci_plot["status"] == "ok"
        @test occursin("<svg", aci_plot["body"])

        observed_config = (
            :Weather => (
                PFD = 300,
                CO2 = 400,
                RH = 60,
                T_air = 4.5,
                wind = 2.0,
            ),
            :Nitrogen => (
                _a = 0.0004,
                _b = 0.0120,
                _c = 0,
                SPAD = 60,
            ),
            :StomataTuzet => (
                sf = 2.3,
                Ψf = -1.2,
            ),
            :ModelC3MD => (
                Vcm25 = 14.0,
                Jm25 = 20.0,
            ),
            :C3p => (
                Tp25 = 2.6,
            ),
        )
        observed_value = Cropbox.deunitfy(
            simulate(
                LeafGasExchange.ModelC3MD;
                target=[:A_net],
                config=@config(observed_config),
                stop=1u"hr",
                verbose=false,
            )[end, :A_net],
        )
        observed = Dict(
            "type" => "DataFrame",
            "columns" => [
                Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                Dict("name" => "A_net", "type" => "Float64", "unit" => "μmol/m^2/s"),
            ],
            "rows" => [[1, observed_value]],
        )

        evaluation = Cropbox.evaluate_payload(
            LeafGasExchange.ModelC3MD,
            Dict(
                "config" => gas_config,
                "observed" => observed,
                "target" => "A_net",
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "metric" => "rmse",
            ),
        )
        @test evaluation["status"] == "ok"
        @test evaluation["operation"] == "evaluate"
        @test 0 < evaluation["value"]["value"] < 0.5

        gas_evaluate_request = Dict(
            "config" => gas_config,
            "observed" => observed,
            "target" => "A_net",
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "metric" => "rmse",
        )
        status, content_type, body = Cropbox.route_api_response(
            LeafGasExchange.ModelC3MD,
            "POST",
            "/api/evaluate",
            JSON3.write(gas_evaluate_request),
        )
        routed_evaluation = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_evaluation["operation"] == "evaluate"
        @test 0 < routed_evaluation["value"]["value"] < 0.5

        gas_calibrate_request = Dict(
            "config" => gas_config,
            "observed" => observed,
            "target" => "A_net",
            "stop" => Dict("value" => 1, "unit" => "hr"),
            "metric" => "rmse",
            "parameters" => [
                Dict(
                    "system" => "C3p",
                    "name" => "Tp25",
                    "lower" => 2.4,
                    "upper" => 3.4,
                ),
            ],
            "optim" => Dict("MaxSteps" => 8, "TraceMode" => "silent"),
        )
        calibration = Cropbox.calibrate_payload(LeafGasExchange.ModelC3MD, gas_calibrate_request)
        @test calibration["status"] == "ok"
        @test calibration["operation"] == "calibrate"
        fitted = calibration["config"]["C3p"]["Tp25"]["value"]
        @test 2.4 <= fitted <= 3.4

        status, content_type, body = Cropbox.route_api_response(
            LeafGasExchange.ModelC3MD,
            "POST",
            "/api/calibrate",
            JSON3.write(gas_calibrate_request),
        )
        routed_calibration = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test routed_calibration["operation"] == "calibrate"
        routed_fitted = routed_calibration["config"]["C3p"]["Tp25"]["value"]
        @test 2.4 <= routed_fitted <= 3.4

        closed_config = merge_api_config(gas_config, routed_calibration["config"])
        closed_evaluation = Cropbox.evaluate_payload(
            LeafGasExchange.ModelC3MD,
            Dict(
                "config" => closed_config,
                "observed" => observed,
                "target" => "A_net",
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "metric" => "rmse",
            ),
        )
        @test closed_evaluation["status"] == "ok"
        @test closed_evaluation["summary"]["nobs"] == 1
        @test isfinite(closed_evaluation["value"]["value"])
    end
    else
        @info "Skipping LeafGasExchange Web API integration tests; package is not available in the active environment"
    end

    if WEBAPI_HAS_GARLIC
    @testset "Garlic CSV application API route example" begin
        timezone = tz"America/Los_Angeles"
        weather_path = joinpath(@__DIR__, "../examples/data/garlic/cuh_2014_weather.csv")
        weather_columns = [
            Dict("name" => "index", "type" => "ZonedDateTime", "timezone" => string(timezone)),
            Dict("name" => "SolRad", "type" => "Float64", "unit" => "W/m^2"),
            Dict("name" => "RH", "type" => "Float64", "unit" => "percent"),
            Dict("name" => "Tair", "type" => "Float64", "unit" => "°C"),
            Dict("name" => "Wind", "type" => "Float64", "unit" => "m/s"),
        ]
        weather_entry = Dict(
            "path" => "Weather.s",
            "value" => Dict(
                "type" => "CSV",
                "filename" => basename(weather_path),
                "content" => read(weather_path, String),
                "columns" => weather_columns,
            ),
        )
        garlic_config = @config(
            Garlic.Examples.AoB.KM,
            Garlic.Examples.AoB.CUH,
            Garlic.Examples.AoB.P2,
            (
                :Calendar => (
                    init = ZonedDateTime(2014, 9, 1, 1, timezone),
                    last = ZonedDateTime(2015, 7, 7, timezone),
                ),
                :Meta => (year = 2014,),
                :Phenology => (
                    storage_days = 143,
                    planting_date = ZonedDateTime(2014, 11, 20, timezone),
                    emergence_date = ZonedDateTime(2014, 12, 30, timezone),
                    scape_removal_date = nothing,
                ),
            ),
        )
        weather_config = Cropbox.normalize_request(
            Garlic.Model,
            Dict("config_entries" => [weather_entry]),
        )["config"]
        garlic_effective_config = Cropbox.configure(garlic_config, weather_config)
        garlic_target = [
            :DAP,
            :leaves_appeared,
            :leaves_mature,
            :leaves_dropped,
            :green_leaf_area,
            :leaf_mass,
            :bulb_mass,
            :total_mass,
        ]
        garlic_target_names = String.(garlic_target)

        status, content_type, body = Cropbox.route_api_response(
            Garlic.Model,
            "GET",
            "/api/model",
            "";
            config=garlic_config,
        )
        garlic_model = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test garlic_model["model"]["module"] == "Garlic"
        @test any(v -> v["name"] == "leaves_appeared" &&
                       v["target_path"] == "leaves_appeared", garlic_model["variables"])
        @test all(v -> !occursin("typefor", something(v["type"], "")), garlic_model["variables"])
        @test any(v -> v["name"] == "leaf_mass" &&
                       !isnothing(v["unit"]) &&
                       v["role"] == "output", garlic_model["variables"])
        @test any(t -> t["role"] == "table" &&
                       haskey(t, "consumers") &&
                       length(t["consumers"]) > 0, garlic_model["tables"])

        request = Dict(
            "config_entries" => [weather_entry],
            "stop" => "calendar.count",
            "snap" => Dict("value" => 1, "unit" => "d"),
            "target" => garlic_target_names,
        )
        status, content_type, body = Cropbox.route_api_response(
            Garlic.Model,
            "POST",
            "/api/simulate",
            JSON3.write(request);
            config=garlic_config,
        )
        routed = JSON3.read(body, Dict{String,Any})
        direct = simulate(
            Garlic.Model;
            config=garlic_effective_config,
            stop="calendar.count",
            snap=1u"d",
            target=garlic_target,
            verbose=false,
        )
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        assert_table_equivalent(routed, direct; atol=1e-6)
        @test routed["summary"]["nrow"] > 300
        @test routed["columns"][2]["name"] == "DAP"
        @test routed["columns"][2]["unit"] == "d"
        @test routed["rows"][end][3] > 0
        @test routed["rows"][end][8] > 0

        visualize_request = Dict(
            "config_entries" => [weather_entry],
            "stop" => "calendar.count",
            "snap" => Dict("value" => 1, "unit" => "d"),
            "x" => "DAP",
            "y" => ["leaf_mass", "bulb_mass", "total_mass"],
            "kind" => "line",
        )
        status, content_type, body = Cropbox.route_api_response(
            Garlic.Model,
            "POST",
            "/api/visualize",
            JSON3.write(visualize_request);
            config=garlic_config,
        )
        plot = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test plot["status"] == "ok"
        @test plot["content_type"] == "image/svg+xml"
        @test occursin("<svg", plot["body"])

        garlic_ui = Dict(
            "outputs" => garlic_target_names,
            "table_inputs" => [
                Dict(
                    "path" => "Weather.s",
                    "label" => "Hourly weather",
                    "default_filename" => basename(weather_path),
                    "columns" => weather_columns,
                ),
            ],
            "panels" => [
                Dict(
                    "title" => "Leaf development",
                    "x" => "DAP",
                    "y" => ["leaves_appeared", "leaves_mature", "leaves_dropped"],
                    "kind" => "step",
                ),
                Dict(
                    "title" => "Biomass partitioning",
                    "x" => "DAP",
                    "y" => ["leaf_mass", "bulb_mass", "total_mass"],
                    "kind" => "line",
                ),
            ],
        )
        status, content_type, body = Cropbox.route_api_response(
            Garlic.Model,
            "GET",
            "/api/dashboard",
            "";
            config=garlic_config,
            ui=garlic_ui,
        )
        dashboard = JSON3.read(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test length(dashboard["panels"]) == 2
        @test count(c -> c["role"] == "parameter", dashboard["controls"]) ==
              count(c -> c["role"] == "parameter", garlic_model["parameters"]) + 1
        clock_control = only(filter(c -> c["path"] == "Clock.step", dashboard["controls"]))
        @test clock_control["source"] == "runtime"
        @test clock_control["default"] == 1
        @test clock_control["unit"] == "hr"
        @test count(c -> c["role"] == "table", dashboard["controls"]) == 1
        @test length(unique(t["target_path"] for t in dashboard["tables"])) == length(dashboard["tables"])
        @test Set(t["config_path"] for t in dashboard["tables"]) == Set(["Weather.s"])
        @test dashboard["panels"][1]["kind"] == "step"
        @test dashboard["panels"][2]["kind"] == "line"
        @test dashboard["panels"][1]["x"] == "pheno.DAP"
        @test "pheno.leaves_appeared" in dashboard["panels"][1]["y"]
        @test "pheno.DAP" in dashboard["visualize"]["x"]["options"]
        @test "leaf_mass" in dashboard["visualize"]["y"]["options"]
        @test any(c -> c["role"] == "table" &&
                       c["kind"] == "file" &&
                       c["accept"] == ".csv,text/csv" &&
                       c["default_filename"] == basename(weather_path) &&
                       c["columns"] == weather_columns, dashboard["controls"])
    end
    else
        @info "Skipping Garlic Web API integration tests; package is not available in the active environment"
    end

    if WEBAPI_HAS_LEAFGASEXCHANGE && WEBAPI_HAS_GARLIC
    @testset "real package serve HTTP round trips" begin
        gas_config = Dict(
            "Weather" => Dict(
                "PFD" => 300,
                "CO2" => 400,
                "RH" => 60,
                "T_air" => 4.5,
                "wind" => 2.0,
            ),
            "Nitrogen" => Dict(
                "_a" => 0.0004,
                "_b" => 0.0120,
                "_c" => 0,
                "SPAD" => 60,
            ),
            "StomataTuzet" => Dict(
                "sf" => 2.3,
                "Ψf" => -1.2,
            ),
            "ModelC3MD" => Dict(
                "Vcm25" => 14.0,
                "Jm25" => 20.0,
            ),
            "C3p" => Dict(
                "Tp25" => 2.8,
            ),
        )
        gas_config_julia = (
            :Weather => (
                PFD = 300,
                CO2 = 400,
                RH = 60,
                T_air = 4.5,
                wind = 2.0,
            ),
            :Nitrogen => (
                _a = 0.0004,
                _b = 0.0120,
                _c = 0,
                SPAD = 60,
            ),
            :StomataTuzet => (
                sf = 2.3,
                Ψf = -1.2,
            ),
            :ModelC3MD => (
                Vcm25 = 14.0,
                Jm25 = 20.0,
            ),
            :C3p => (
                Tp25 = 2.8,
            ),
        )

        gas_server = Cropbox.serve(
            LeafGasExchange.ModelC3MD;
            host="127.0.0.1",
            port=0,
            async=true,
            config=gas_config_julia,
            ui=Dict(
                "outputs" => ["Ci", "A_net", "Ac", "Aj", "Ap"],
                "panels" => [
                    Dict("title" => "A-Ci", "x" => "Ci", "y" => ["A_net", "Ac", "Aj", "Ap"], "kind" => "line"),
                ],
            ),
        )
        try
            gas_url = api_server_url(gas_server)

            gas_model, gas_model_response = http_get_json(gas_url, "/api/model")
            @test gas_model_response.status == 200
            @test gas_model["model"]["module"] == "LeafGasExchange"
            @test any(p -> p["name"] == "CO2" &&
                           p["declared_path"] == "Weather.CO2" &&
                           p["config_path"] == "ModelC3MD.CO2" &&
                           "Weather.CO2" in p["accepted_config_paths"], gas_model["parameters"])
            @test any(v -> v["name"] == "A_net" &&
                           !isnothing(v["unit"]) &&
                           occursin("μmol", v["unit"]) &&
                           v["target_path"] == "A_net", gas_model["variables"])

            gas_dashboard, gas_dashboard_response = http_get_json(gas_url, "/api/dashboard")
            @test gas_dashboard_response.status == 200
            @test gas_dashboard["panels"][1]["kind"] == "line"
            @test "A_net" in gas_dashboard["visualize"]["y"]["options"]
            @test any(c -> c["path"] == "ModelC3MD.CO2" &&
                           !isnothing(c["unit"]) &&
                           occursin("μmol", c["unit"]), gas_dashboard["controls"])

            gas_request = Dict(
                "config_entries" => Dict("Weather.CO2" => 420),
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "target" => ["A_net", "Ac", "Aj", "Ap", "Ci"],
            )
            gas_routed, gas_sim_response = http_post_json(gas_url, "/api/simulate", gas_request)
            gas_direct = simulate(
                LeafGasExchange.ModelC3MD;
                config=Cropbox.configure(gas_config_julia, :Weather => :CO2 => 420),
                stop=1u"hr",
                target=[:A_net, :Ac, :Aj, :Ap, :Ci],
                verbose=false,
            )
            @test gas_sim_response.status == 200
            assert_table_equivalent(gas_routed, gas_direct; atol=1e-6)

            gas_plot, gas_plot_response = http_post_json(
                gas_url,
                "/api/visualize",
                Dict(
                    "config_entries" => Dict("Weather.CO2" => 420),
                    "x" => "Ci",
                    "y" => ["A_net", "Ac", "Aj", "Ap"],
                    "xstep" => Dict("path" => "Weather.CO2", "start" => 330, "stop" => 470, "step" => 20),
                    "kind" => "line",
                ),
            )
            @test gas_plot_response.status == 200
            @test gas_plot["status"] == "ok"
            @test gas_plot["content_type"] == "image/svg+xml"
            @test occursin("<svg", gas_plot["body"])

            gas_observed_config = (
                :Weather => (
                    PFD = 300,
                    CO2 = 400,
                    RH = 60,
                    T_air = 4.5,
                    wind = 2.0,
                ),
                :Nitrogen => (
                    _a = 0.0004,
                    _b = 0.0120,
                    _c = 0,
                    SPAD = 60,
                ),
                :StomataTuzet => (
                    sf = 2.3,
                    Ψf = -1.2,
                ),
                :ModelC3MD => (
                    Vcm25 = 14.0,
                    Jm25 = 20.0,
                ),
                :C3p => (
                    Tp25 = 2.6,
                ),
            )
            gas_observed_value = Cropbox.deunitfy(
                simulate(
                    LeafGasExchange.ModelC3MD;
                    target=[:A_net],
                    config=@config(gas_observed_config),
                    stop=1u"hr",
                    verbose=false,
                )[end, :A_net],
            )
            gas_observed = Dict(
                "type" => "DataFrame",
                "columns" => [
                    Dict("name" => "time", "type" => "Float64", "unit" => "hr"),
                    Dict("name" => "A_net", "type" => "Float64", "unit" => "μmol/m^2/s"),
                ],
                "rows" => [[1, gas_observed_value]],
            )
            gas_obs_df = DataFrame(time=[1]u"hr", A_net=[gas_observed_value]u"μmol/m^2/s")
            gas_eval_request = Dict(
                "observed" => gas_observed,
                "target" => "A_net",
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "metric" => "rmse",
            )
            gas_eval, gas_eval_response = http_post_json(gas_url, "/api/evaluate", gas_eval_request)
            gas_eval_direct = evaluate(
                LeafGasExchange.ModelC3MD,
                gas_obs_df;
                config=gas_config_julia,
                target=:A_net,
                stop=1u"hr",
                metric=:rmse,
                verbose=false,
            )
            @test gas_eval_response.status == 200
            @test gas_eval["operation"] == "evaluate"
            @test isapprox(gas_eval["value"]["value"], Cropbox.deunitfy(gas_eval_direct); atol=1e-8, rtol=1e-8)

            gas_calibrate_request = Dict(
                "observed" => gas_observed,
                "target" => "A_net",
                "stop" => Dict("value" => 1, "unit" => "hr"),
                "metric" => "rmse",
                "parameters" => [
                    Dict(
                        "system" => "C3p",
                        "name" => "Tp25",
                        "lower" => 2.4,
                        "upper" => 3.4,
                    ),
                ],
                "optim" => Dict("MaxSteps" => 8, "TraceMode" => "silent"),
            )
            gas_calibration, gas_calibration_response = http_post_json(gas_url, "/api/calibrate", gas_calibrate_request; readtimeout=120)
            @test gas_calibration_response.status == 200
            @test gas_calibration["operation"] == "calibrate"
            @test gas_calibration["summary"]["nparameters"] == 1
            @test 2.4 <= gas_calibration["config"]["C3p"]["Tp25"]["value"] <= 3.4
        finally
            close(gas_server)
        end

        timezone = tz"America/Los_Angeles"
        weather_path = joinpath(@__DIR__, "../examples/data/garlic/cuh_2014_weather.csv")
        weather_columns = [
            Dict("name" => "index", "type" => "ZonedDateTime", "timezone" => string(timezone)),
            Dict("name" => "SolRad", "type" => "Float64", "unit" => "W/m^2"),
            Dict("name" => "RH", "type" => "Float64", "unit" => "percent"),
            Dict("name" => "Tair", "type" => "Float64", "unit" => "°C"),
            Dict("name" => "Wind", "type" => "Float64", "unit" => "m/s"),
        ]
        weather_entry = Dict(
            "path" => "Weather.s",
            "value" => Dict(
                "type" => "CSV",
                "filename" => basename(weather_path),
                "content" => read(weather_path, String),
                "columns" => weather_columns,
            ),
        )
        garlic_config = @config(
            Garlic.Examples.AoB.KM,
            Garlic.Examples.AoB.CUH,
            Garlic.Examples.AoB.P2,
            (
                :Calendar => (
                    init = ZonedDateTime(2014, 9, 1, 1, timezone),
                    last = ZonedDateTime(2015, 7, 7, timezone),
                ),
                :Meta => (year = 2014,),
                :Phenology => (
                    storage_days = 143,
                    planting_date = ZonedDateTime(2014, 11, 20, timezone),
                    emergence_date = ZonedDateTime(2014, 12, 30, timezone),
                    scape_removal_date = nothing,
                ),
            ),
        )
        weather_config = Cropbox.normalize_request(
            Garlic.Model,
            Dict("config_entries" => [weather_entry]),
        )["config"]
        garlic_effective_config = Cropbox.configure(garlic_config, weather_config)
        garlic_target = [
            :DAP,
            :leaves_appeared,
            :leaf_mass,
            :bulb_mass,
            :total_mass,
        ]
        garlic_target_names = String.(garlic_target)
        garlic_ui = Dict(
            "outputs" => garlic_target_names,
            "table_inputs" => [
                Dict(
                    "path" => "Weather.s",
                    "label" => "Hourly weather",
                    "default_filename" => basename(weather_path),
                    "columns" => weather_columns,
                ),
            ],
            "panels" => [
                Dict("title" => "Leaf appearance", "x" => "DAP", "y" => ["leaves_appeared"], "kind" => "step"),
                Dict("title" => "Biomass", "x" => "DAP", "y" => ["leaf_mass", "bulb_mass", "total_mass"], "kind" => "line"),
            ],
        )
        garlic_server = Cropbox.serve(
            Garlic.Model;
            host="127.0.0.1",
            port=0,
            async=true,
            config=garlic_config,
            request_defaults=Dict("config_entries" => [weather_entry]),
            ui=garlic_ui,
        )
        try
            garlic_url = api_server_url(garlic_server)

            garlic_model, garlic_model_response = http_get_json(garlic_url, "/api/model")
            @test garlic_model_response.status == 200
            @test garlic_model["model"]["module"] == "Garlic"
            @test any(t -> t["role"] == "table" &&
                           any(c -> c["name"] == "T_air" && c["column"] == "Tair", t["consumers"]), garlic_model["tables"])
            @test any(v -> v["name"] == "leaf_mass" &&
                           v["role"] == "output" &&
                           !isnothing(v["unit"]), garlic_model["variables"])

            garlic_dashboard, garlic_dashboard_response = http_get_json(garlic_url, "/api/dashboard")
            @test garlic_dashboard_response.status == 200
            @test length(garlic_dashboard["panels"]) == 2
            @test garlic_dashboard["panels"][1]["x"] == "pheno.DAP"
            @test "pheno.leaves_appeared" in garlic_dashboard["panels"][1]["y"]
            @test any(c -> c["role"] == "table" &&
                           c["kind"] == "file" &&
                           c["accept"] == ".csv,text/csv" &&
                           c["columns"] == weather_columns, garlic_dashboard["controls"])

            garlic_request = Dict(
                "stop" => "calendar.count",
                "snap" => Dict("value" => 1, "unit" => "d"),
                "target" => garlic_target_names,
            )
            garlic_routed, garlic_sim_response = http_post_json(garlic_url, "/api/simulate", garlic_request; readtimeout=120)
            garlic_direct = simulate(
                Garlic.Model;
                config=garlic_effective_config,
                stop="calendar.count",
                snap=1u"d",
                target=garlic_target,
                verbose=false,
            )
            @test garlic_sim_response.status == 200
            assert_table_equivalent(garlic_routed, garlic_direct; atol=1e-6)
            @test garlic_routed["summary"]["nrow"] > 300
            @test garlic_routed["rows"][end][3] > 0

            uploaded_entry = deepcopy(weather_entry)
            uploaded_entry["value"]["filename"] = "uploaded_weather.csv"
            uploaded_request = merge(
                garlic_request,
                Dict("config_entries" => [uploaded_entry]),
            )
            uploaded_routed, uploaded_response = http_post_json(
                garlic_url,
                "/api/simulate",
                uploaded_request;
                readtimeout=120,
            )
            @test uploaded_response.status == 200
            @test uploaded_routed["rows"] == garlic_routed["rows"]

            garlic_plot, garlic_plot_response = http_post_json(
                garlic_url,
                "/api/visualize",
                Dict(
                    "stop" => "calendar.count",
                    "snap" => Dict("value" => 1, "unit" => "d"),
                    "x" => "DAP",
                    "y" => ["leaf_mass", "bulb_mass", "total_mass"],
                    "kind" => "line",
                );
                readtimeout=120,
            )
            @test garlic_plot_response.status == 200
            @test garlic_plot["status"] == "ok"
            @test garlic_plot["content_type"] == "image/svg+xml"
            @test occursin("<svg", garlic_plot["body"])
        finally
            close(garlic_server)
        end
    end
    else
        @info "Skipping real-package HTTP round trips; LeafGasExchange and Garlic are required"
    end

    @testset "visualize xstep request" begin
        @system SWebAPISweep(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) => 2a ~ track
        end

        request = Dict(
            "config" => Dict("SWebAPISweep" => Dict("a" => 1)),
            "x" => "a",
            "y" => "b",
            "xstep" => Dict(
                "system" => "SWebAPISweep",
                "name" => "a",
                "start" => 1,
                "stop" => 3,
                "step" => 1,
            ),
        )
        response = Cropbox.visualize_payload(SWebAPISweep, request)
        @test response["status"] == "ok"
        @test response["content_type"] == "image/svg+xml"
        @test occursin("<svg", response["body"])

        unit_request = Dict(
            "config" => Dict("SWebAPI" => Dict("a" => Dict("value" => 1, "unit" => "m"))),
            "x" => "a",
            "y" => "b",
            "xstep" => Dict(
                "system" => "SWebAPI",
                "name" => "a",
                "start" => 1,
                "stop" => 2,
                "step" => 0.5,
                "unit" => "m",
            ),
        )
        unit_response = Cropbox.visualize_payload(SWebAPI, unit_request)
        @test unit_response["status"] == "ok"
        @test unit_response["content_type"] == "image/svg+xml"
        @test occursin("<svg", unit_response["body"])
    end
end
