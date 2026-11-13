using GlobalSensitivity, Random, Unitful
isdefined(@__MODULE__, :MCalibrateUnit) || include("parameters.jl")

@testset "analyze" begin
    @system SAnalyze(Controller) begin
        a: aa => 0.5 ~ preserve(parameter)
        b     => 0.5 ~ preserve(parameter)
        c     => 0.5 ~ preserve(parameter)
        sign  => 1.0 ~ preserve(parameter)

        y(a, b, c, sign) => sign * (a + 2b + 3c) ~ track
        total(y)                                 ~ accumulate
    end

    P = SAnalyze => (; a = (0, 1), b = (0, 1))
    method = Morris(num_trajectory = 20, len_design_mat = 20)
    rng = Xoshiro(42)
    gsa = (; rng)
    before = deepcopy(P), deepcopy(rng)

    r = analyze(SAnalyze; target = :y, parameters = P, method, gsa, stop = 0)
    @test r.table.parameter == [:a, :b]
    @test r.table.target == [:y, :y]
    @test r.table.means ≈ [1, 2]
    @test r.table.means_star ≈ [1, 2]
    @test r.raw isa GlobalSensitivity.MorrisResult
    @test isempty(method.p_steps)
    @test P == before[1] && rng == before[2]

    @testset "conditions and targets" begin
        configs = [SAnalyze => :sign => s for s in (1, -1)]
        r = analyze(SAnalyze; target = [:y, :total], parameters = P, configs, method, gsa, stop = 2)
        @test r.table.config == repeat([1, 1, 2, 2], 2)
        @test r.table.target == repeat([:y, :total], 4)
        @test r.table.means ≈ [1, 2, -1, -2, 2, 4, -2, -4]
        @test configs == [SAnalyze => :sign => s for s in (1, -1)]

        r = analyze(SAnalyze; target = :response => :y, parameters = SAnalyze => :aa => (0, 1),
            method, gsa, stop = 0)
        @test r.table.parameter == [:aa]
        @test r.table.target == [:response]
        @test only(r.table.means) ≈ 1

        @system SAnalyzeNested(Controller) begin
            child(context, config) ~ ::SAnalyze
        end
        r = analyze(SAnalyzeNested; base = :child, target = :y, parameters = P, method, gsa, stop = 0)
        @test r.table.means ≈ [1, 2]
    end

    @testset "endpoint and summary" begin
        r = analyze(SAnalyze; target = :total, parameters = P, method, gsa, stop = 3, snap = 2u"hr")
        @test r.table.means ≈ [3, 6]

        calls = Ref(0)
        lasttime = Ref(0.0u"hr")
        summary(df) = begin
            calls[] += 1
            lasttime[] = df.time[end]
            maximum(df.total)
        end
        r = analyze(summary, SAnalyze; target = :total, parameters = P, method, gsa, stop = 3, snap = 2u"hr")
        @test r.table.target == [:summary, :summary]
        @test r.table.means ≈ [2, 4]
        @test calls[] == method.num_trajectory * method.len_design_mat
        @test lasttime[] == 2u"hr"

        @test_throws ArgumentError analyze(_ -> [1, 2], SAnalyze; target = :y, parameters = P, stop = 0)
        @test_throws ArgumentError analyze(_ -> NaN, SAnalyze; target = :y, parameters = P, stop = 0)
        @test_throws ArgumentError analyze(_ -> big"1e1000", SAnalyze; target = :y, parameters = P, stop = 0)
        @test_throws ArgumentError analyze(only, SAnalyze; target = :y, parameters = P, stop = 0, snap = false)
    end

    @testset "units and parameter ranges" begin
        @system SAnalyzeUnit(Controller) begin
            a => 0.5 ~ preserve(parameter, u"g/hr")
            b => 0.5 ~ preserve(parameter, u"g/hr")

            y(a, b) => a + 2b ~ track(u"g/hr")
            total(y)          ~ accumulate(u"g")
        end

        p = SAnalyzeUnit => (; a = (0, 1), b = (0, 1))
        q = :0 => (; a = [0, 1000]u"mg/hr", b = [0, 1000]u"mg/hr")
        r = analyze(SAnalyzeUnit; target = :total, parameters = p, method, gsa, stop = 2)
        s = analyze(SAnalyzeUnit; target = :total, parameters = q, method, gsa, stop = 2)
        @test r.table.means ≈ [2, 4]u"g"
        @test r.table.means_star ≈ s.table.means_star
        @test r.table.lower == s.table.lower && r.table.upper == s.table.upper
        @test all(v -> Unitful.unit(v) == u"g^2", r.table.variances)

        r = analyze(SAnalyzeUnit; target = [:y, :total], parameters = p, method, gsa, stop = 2)
        @test all(isapprox.(r.table.means[r.table.target .== :y], [1, 2]u"g/hr"))
        @test all(isapprox.(r.table.means[r.table.target .== :total], [2, 4]u"g"))

        r = analyze(SAnalyzeUnit; target = :total, parameters = p,
            method = Morris(relative_scale = true), gsa, stop = 2)
        @test all(v -> v isa Real, r.table.means)

        r = analyze(SAnalyze; target = :y, parameters = SAnalyze => (; a = (0, 2), b = (0, 1)),
            method, gsa, stop = 0)
        @test r.table.means ≈ [2, 2]

        @system SAnalyzeTemperature(Controller) begin
            temperature => 0 ~ preserve(parameter, u"°C")
        end
        r = analyze(SAnalyzeTemperature;
            target = :temperature, parameters = SAnalyzeTemperature => :temperature => [0, 10]u"°C",
            method, gsa, stop = 0)
        @test only(r.table.means) ≈ 10u"K"
    end

    @testset "module parameters" begin
        method = Morris(num_trajectory = 4, total_num_trajectory = 4, len_design_mat = 4)
        for S in (MCalibrateUnit.Model, MCalibrateOuter.Model)
            r = analyze(S; target = :b => "g.b", parameters = :Growth => :rate => (0, 1),
                method, gsa, stop = 10)
            @test only(r.table.means) ≈ 0.1u"m"
            @test only(r.table.upper) == 1u"cm/hr"
        end
        @test_throws ArgumentError analyze(MCalibrateOuter.PairModel; target = :b => "g.b",
            parameters = :Growth => :rate => (0, 1), stop = 10)
        @test_throws ArgumentError analyze(MCalibrateOuter.Model; target = :b => "g.b",
            parameters = :MissingGrowth => :rate => (0, 1), stop = 10)

        for S in (MCalibrateUnit.Dynamic, MCalibrateOuter.Unspecified)
            r = @test_logs (:warn, r"cannot verify whether dynamic parameters") analyze(S;
                target = :a => "g[1].a", parameters = MCalibrateUnit.Growth => :rate => (0, 1),
                method, gsa, stop = 1)
            @test only(r.table.means) ≈ 1u"cm/hr"
        end
    end

    @testset "variance methods" begin
        for method in (:sobol, :efast)
            p = SAnalyze => (; a = (0, 1), b = (0, 1), c = (0, 1))
            opts = method == :sobol ? (; samples = 1024) : (; samples = 1024, rng = Xoshiro(42))
            r = analyze(SAnalyze; target = [:y], parameters = p, method, gsa = opts, stop = 0)
            @test r.table.S1 ≈ [1, 4, 9] ./ 14 atol = 0.02
            @test r.table.ST ≈ [1, 4, 9] ./ 14 atol = 0.02
        end

        r = analyze(SAnalyze; target = :y, parameters = P,
            method = Sobol(order = [0, 1, 2], nboot = 2), gsa = (; samples = 128), stop = 0)
        @test !isnothing(r.raw.S2)
        @test !isnothing(r.raw.S1_Conf_Int)

        r = analyze(SAnalyze; target = :y, parameters = P, configs = [SAnalyze => :sign => s for s in (1, -1)],
            method = :sobol, gsa = (; samples = 256), stop = 0)
        @test r.table.S1 ≈ [0.2, 0.2, 0.8, 0.8] atol = 0.02

        @test_throws ArgumentError analyze(_ -> 1.0, SAnalyze; target = :y, parameters = P,
            method = :sobol, gsa = (; samples = 16), stop = 0)
    end

    @testset "validation" begin
        @system SAnalyzeDiscrete(Controller) begin
            a => 1 ~ preserve::int(parameter)
            b => 1 ~ preserve::int(parameter, u"g")
        end

        for (method, gsa) in (
            (:unknown, (;)),

            (:morris, (; samples = 128)),
            (:morris, (; num_trajectory = 20)), (Morris(p_steps = [1, 1]), (;)),

            (:sobol, (; rng = Xoshiro(42))), (:sobol, (;)), (:sobol, (; samples = 0)),
            (:sobol, (; samples = 16, Ei_estimator = :typo)),

            (:efast, (; samples = 16)), (:efast, (; samples = 1024)),
            (:efast, (; samples = 128, typo = 1)),

            (:morris, (; batch = true)),
        )
            @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = P, method, gsa, stop = 0)
        end

        for bounds in ((0, 0), (1, 0), (0, Inf), [0, 1, 2])
            @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = SAnalyze => :a => bounds, stop = 0)
        end

        @test_throws UndefKeywordError analyze(SAnalyze; target = :y, parameters = P)
        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = P, stop = nothing)

        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = (), stop = 0)
        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = :SAnalyze => :typo => (0, 1), stop = 0)
        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = :SAnalyze => :y => (0, 1), stop = 0)

        @test_throws ArgumentError analyze(SAnalyzeDiscrete; target = :a, parameters = SAnalyzeDiscrete => :a => (0, 2), stop = 0)
        @test_throws ArgumentError analyze(SAnalyzeDiscrete; target = :b, parameters = SAnalyzeDiscrete => :b => (0, 2), stop = 0)
        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = SAnalyze => (; a = (0, 1), aa = (0, 1)), stop = 0)

        @test_throws ArgumentError analyze(SAnalyze; target = [], parameters = P, stop = 0)
        @test_throws ArgumentError analyze(SAnalyze; target = nothing, parameters = P, stop = 0)
        @test_throws ArgumentError analyze(SAnalyze; target = "*", parameters = P, stop = 0)

        @test_throws ArgumentError analyze(SAnalyze; target = :y, parameters = P, config = P, configs = [P], stop = 0)
    end
end
