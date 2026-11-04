using Cropbox
using Test
using CSV
using DataFrames
using Dates
using JSON
using TimeZones
using Garlic
using LeafGasExchange
using SimpleCrop

const API_TEST_ATOL = 1e-9
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
    merged = JSON.parse(JSON.json(base), Dict{String,Any})
    for (system, fields) in fitted
        target = get!(merged, system, Dict{String,Any}())
        for (name, value) in fields
            target[name] = value
        end
    end
    merged
end

api_server_url(server) = "http://127.0.0.1:$(Cropbox.HTTP.port(server))"

function http_get_json(base_url, path; read_idle_timeout=API_TEST_READTIMEOUT)
    response = Cropbox.HTTP.get("$base_url$path"; read_idle_timeout)
    JSON.parse(String(response.body), Dict{String,Any}), response
end

function http_post_json(base_url, path, payload; read_idle_timeout=API_TEST_READTIMEOUT)
    response = Cropbox.HTTP.request(
        "POST",
        "$base_url$path",
        ["Content-Type" => "application/json"],
        JSON.json(payload);
        read_idle_timeout,
    )
    JSON.parse(String(response.body), Dict{String,Any}), response
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

end

@testset "webapi integration" begin
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
        model = JSON.parse(body, Dict{String,Any})
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
            JSON.json(request);
            config=pheno_config,
        )
        routed = JSON.parse(body, Dict{String,Any})
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
            JSON.json(visualize_request);
            config=pheno_config,
        )
        plot = JSON.parse(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
    end

    @testset "SimpleCrop CSV API route equivalence" begin
        weather_csv = read(joinpath(@__DIR__, "../../test/examples/data/simplecrop/weather.csv"), String)
        irrigation_csv = read(joinpath(@__DIR__, "../../test/examples/data/simplecrop/irrigation.csv"), String)
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
            JSON.json(request),
        )
        routed = JSON.parse(body, Dict{String,Any})
        direct = simulate(
            SimpleCrop.Model;
            config=@config(
                :Clock => :step => 1u"d",
                :Calendar => :init => ZonedDateTime(1987, 1, 1, tz"UTC"),
                :Weather => :weather_data => DataFrame(CSV.File(joinpath(@__DIR__, "../../test/examples/data/simplecrop/weather.csv"))),
                :SoilWater => :irrigation_data => DataFrame(CSV.File(joinpath(@__DIR__, "../../test/examples/data/simplecrop/irrigation.csv"))),
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
            JSON.json(visualize_request),
        )
        plot = JSON.parse(body, Dict{String,Any})
        @test status == 200
        @test content_type == "application/json; charset=utf-8"
        @test plot["status"] == "ok"
        @test occursin("<svg", plot["body"])
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
        @test only(v["unit"] for v in describe(SWebAPIGDD)["variables"] if v["name"] == "TT") == "K*d"

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
            JSON.json(gdd_evaluate_request),
        )
        routed_evaluation = JSON.parse(body, Dict{String,Any})
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
            JSON.json(gdd_calibrate_request),
        )
        routed_calibration = JSON.parse(body, Dict{String,Any})
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
        @test only(v["unit"] for v in describe(SWebAPICF)["variables"] if v["name"] == "forcing") == "K*d"

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
            JSON.json(cf_evaluate_request),
        )
        routed_evaluation = JSON.parse(body, Dict{String,Any})
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
            JSON.json(cf_calibrate_request),
        )
        routed_calibration = JSON.parse(body, Dict{String,Any})
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
            JSON.json(gas_evaluate_request),
        )
        routed_evaluation = JSON.parse(body, Dict{String,Any})
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
            JSON.json(gas_calibrate_request),
        )
        routed_calibration = JSON.parse(body, Dict{String,Any})
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

    @testset "Garlic CSV application API route example" begin
        timezone = tz"America/Los_Angeles"
        weather_path = joinpath(@__DIR__, "../../test/examples/data/garlic/cuh_2014_weather.csv")
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
        garlic_model = JSON.parse(body, Dict{String,Any})
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
            JSON.json(request);
            config=garlic_config,
        )
        routed = JSON.parse(body, Dict{String,Any})
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
            JSON.json(visualize_request);
            config=garlic_config,
        )
        plot = JSON.parse(body, Dict{String,Any})
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
        dashboard = JSON.parse(body, Dict{String,Any})
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
            gas_calibration, gas_calibration_response = http_post_json(gas_url, "/api/calibrate", gas_calibrate_request; read_idle_timeout=120)
            @test gas_calibration_response.status == 200
            @test gas_calibration["operation"] == "calibrate"
            @test gas_calibration["summary"]["nparameters"] == 1
            @test 2.4 <= gas_calibration["config"]["C3p"]["Tp25"]["value"] <= 3.4
        finally
            close(gas_server)
        end

        timezone = tz"America/Los_Angeles"
        weather_path = joinpath(@__DIR__, "../../test/examples/data/garlic/cuh_2014_weather.csv")
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
            garlic_routed, garlic_sim_response = http_post_json(garlic_url, "/api/simulate", garlic_request; read_idle_timeout=120)
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
                read_idle_timeout=120,
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
                read_idle_timeout=120,
            )
            @test garlic_plot_response.status == 200
            @test garlic_plot["status"] == "ok"
            @test garlic_plot["content_type"] == "image/svg+xml"
            @test occursin("<svg", garlic_plot["body"])
        finally
            close(garlic_server)
        end
    end

end
