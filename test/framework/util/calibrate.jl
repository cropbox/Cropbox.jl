using DataFrames
isdefined(@__MODULE__, :MCalibrateUnit) || include("parameters.jl")

@testset "calibrate" begin
    @testset "basic" begin
        @system SCalibrate(Controller) begin
            a => 0 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        t, a, b = 10.0u"hr", 20, 200
        A = (0.0, 100.0)
        obs = DataFrame(time=[t], b=[b])
        p = calibrate(SCalibrate, obs, stop=n, target=:b, parameters=("SCalibrate.a" => A))
        @test p[:SCalibrate][:a] == a
        r = simulate(SCalibrate, stop=n, config=p)
        @test r[r.time .== t, :][1, :b] == b
    end

    @testset "unit" begin
        @system SCalibrateUnit(Controller) begin
            a => 0 ~ preserve(parameter, u"cm/hr")
            b(a) ~ accumulate(u"m")
        end
        n = 10
        t, a, b = 10.0u"hr", 20u"cm/hr", 200u"cm"
        A = [0, 1]u"m/hr"
        obs = DataFrame(time=[t], b=[b])
        p = calibrate(SCalibrateUnit, obs, stop=n, target=:b, parameters=("SCalibrateUnit.a" => A))
        @test p[:SCalibrateUnit][:a] ≈ a
        r = simulate(SCalibrateUnit, stop=n, config=p)
        @test r[r.time .== t, :][1, :b] == b
    end

    @testset "module units" begin
        S = MCalibrateOuter.Model
        target = :b => "g.b"
        obs = DataFrame(time = [10.0]u"hr", b = [200.0]u"cm")
        optim = (; MaxSteps = 2000, TraceMode = :silent)
        for bounds in ((0.0, 1.0) .* u"m/hr", (0.0, 100.0))
            p = calibrate(S, obs; target, stop = 10, parameters = :Growth => :rate => bounds, optim)
            @test p[:Growth][:rate] ≈ 20u"cm/hr"
            @test simulate(S; config = p, stop = 10, target)[end, :b] ≈ 2u"m"
        end
    end

    @testset "parameter matching" begin
        S = MCalibrateOuter.Model
        units(S, p) = Cropbox.parameterunits(Cropbox.resolveparameters(Cropbox.configure(p), S))
        for T in (MCalibrateUnit.Growth, MCalibrateUnit.Model, S, MCalibrateOuter.Mixed)
            @test units(T, :Growth => :rate => (0, 1)) == [u"cm/hr"]
        end
        @test units(MCalibrateUnit.Growth, :0 => :rate => (0, 1)) == [u"cm/hr"]
        @test units(MCalibrateOuter.Produced, :Growth => :rate => (0, 1)) == [u"cm/hr"]
        @test_throws ArgumentError units(S, :MissingGrowth => :rate => (0, 1))
        @test_throws ArgumentError units(S, :Growth => :typo => (0, 1))
        @test_throws ArgumentError units(S, :Growth => :b => (0, 1))
        @test_throws ArgumentError units(S, :Growth => (a = (0, 1), rate = (0, 1)))
        @test_throws ArgumentError units(MCalibrateOuter.Mixed,
            (:Mixed => :a => (0, 1), :Growth => :a => (0, 1)))
        @test_throws ArgumentError units(MCalibrateOuter.PairModel, :Growth => :rate => (0, 1))
        @test units(MCalibrateOuter.PairModel, Symbol(MCalibrateUnit.Growth) => :rate => (0, 1)) == [u"cm/hr"]
        @test_throws ArgumentError("parameter Growth.rate is not used by model Fixed") units(MCalibrateOuter.Fixed, :Growth => :rate => (0, 1))

        @system SCalibrateQualified(Controller) begin
            a: rate => 1 ~ preserve(parameter, u"cm/hr")
            _b      => 1 ~ preserve(parameter)

            b(_b) ~ track
        end
        key = Symbol("Main.SCalibrateQualified")
        @test units(SCalibrateQualified, key => :rate => (0, 1)) == [u"cm/hr"]
        @test instance(SCalibrateQualified; config = key => :rate => 2).a' == 2u"cm/hr"
        @test units(SCalibrateQualified, key => :_b => (0, 1)) == [nothing]
        @test instance(SCalibrateQualified; config = key => :_b => 2).b' == 2

        c = (:Growth => :rate => 3, Symbol("Main.MCalibrateUnit.Growth") => :rate => 4)
        s = instance(MCalibrateOuter.PairModel; config = c)
        @test (s.g.a', s.h.a') == (4u"cm/hr", 3u"m/hr")

        obs = DataFrame(time = [10.0]u"hr", b = [0.0]u"m")
        @test_throws ArgumentError calibrate(S, obs; target = :b => "g.b", stop = 10,
            parameters = :MissingGrowth => :rate => (0, 1))
    end

    @testset "dynamic parameters" begin
        resolve(S, p) = Cropbox.resolveparameters(p, S)
        S = MCalibrateUnit.Dynamic
        p = :Child => (; rate = (0, 100), c = (0, 2))
        R = @test_logs (:warn, r"cannot verify whether dynamic parameters") resolve(S, p)
        @test Cropbox.parameterunits(R) == [u"cm/hr", nothing]
        @test_throws ArgumentError("not a parameter: Child.typo") resolve(S, :Child => :typo => (0, 1))
        @test_throws ArgumentError resolve(S, :Child => (; a = (0, 1), rate = (0, 1)))
        @test_throws ArgumentError("system MissingChild is not part of model Dynamic") resolve(S, :MissingChild => :a => (0, 1))

        @test_throws ArgumentError resolve(S, Symbol("Main.MCalibrateOuter.Growth") => :rate => (0, 1))
        @test_throws ArgumentError resolve(S, (:Child => :rate => (0, 1), :Growth => :rate => (0, 1)))
        p = :Growth => :rate => (0, 1)
        R = @test_logs (:warn, r"cannot verify whether dynamic parameters") resolve(S, p)
        @test Cropbox.parameterunits(R) == [u"cm/hr"]
        R = @test_logs (:warn, r"cannot verify whether dynamic parameters") resolve(S, :OtherChild => :rate => (0, 1))
        @test Cropbox.parameterunits(R) == [u"cm/hr"]

        S = MCalibrateOuter.Unspecified
        p = MCalibrateUnit.Growth => :rate => (0, 100)
        R = @test_logs (:warn, r"cannot verify whether dynamic parameters") resolve(S, p)
        @test Cropbox.parameterunits(R) == [u"cm/hr"]
        key = first(names(MCalibrateUnit.Growth))
        R = @test_logs (:warn, r"cannot verify whether dynamic parameters") resolve(S, key => :rate => (0, 100))
        @test Cropbox.parameterunits(R) == [u"cm/hr"]
        @test_throws ArgumentError("cannot resolve system MissingChild for dynamic model Unspecified; use a system type or qualified name") resolve(S, :MissingChild => :a => (0, 1))

        for T in (S, MCalibrateUnit.Dynamic)
            s = instance(T; config = :Growth => :rate => 20)
            update!(s)
            @test only(s.g).a' == 20u"cm/hr"
        end
    end

    @testset "config" begin
        @system SCalibrateConfig(Controller) begin
            a => 0 ~ preserve(parameter)
            w => 1 ~ preserve(parameter)
            b(a, w) => w*a ~ accumulate
        end
        n = 10
        t, a, b = 10.0u"hr", 20, 200
        w1, w2 = 1, 2
        A = (0.0, 100.0)
        obs = DataFrame(time=[t], b=[b])
        params = :SCalibrateConfig => :a => A
        p1 = calibrate(SCalibrateConfig, obs, stop=n, target=:b, config=(:SCalibrateConfig => :w => w1), parameters=params)
        @test p1[:SCalibrateConfig][:a] == a/w1
        p2 = calibrate(SCalibrateConfig, obs, stop=n, target=:b, config=(:SCalibrateConfig => :w => w2), parameters=params)
        @test p2[:SCalibrateConfig][:a] == a/w2
    end

    @testset "configs as index" begin
        @system SCalibrateConfigsIndex(Controller) begin
            a => 0 ~ preserve(parameter)
            w => 1 ~ preserve(parameter)
            b(a, w) => w*a ~ accumulate
        end
        n = 10
        t, w, b = [10.0u"hr", 10.0u"hr"], [1, 2], [100, 200]
        A = (0.0, 100.0)
        obs = DataFrame(; time=t, w, b)
        configs = [
            :SCalibrateConfigsIndex => :w => 1,
            :SCalibrateConfigsIndex => :w => 2,
        ]
        index = [:time => "context.clock.time", :w]
        target = :b
        params = :SCalibrateConfigsIndex => :a => A
        p = calibrate(SCalibrateConfigsIndex, obs, configs; stop=n, index, target, parameters=params)
        @test p[:SCalibrateConfigsIndex][:a] == 10

        optim = (; MaxSteps = 4, PopulationSize = 6, TraceMode = :silent)
        @test_logs calibrate(SCalibrateConfigsIndex, obs, configs; stop = n, index, target, parameters = params, optim)
        p = @test_logs (:warn, r"calibration candidate.*1 of 2 complete observations matched") calibrate(SCalibrateConfigsIndex, obs;
            stop = n, index, target, parameters = params, optim)
        q = @test_logs calibrate(SCalibrateConfigsIndex, obs;
            stop = n, index, target, parameters = params, optim, warn = false)
        @test p[:SCalibrateConfigsIndex][:a] == q[:SCalibrateConfigsIndex][:a]
    end

    @testset "missing observations and empty matches" begin
        @system SCalibrateAlignment(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a)   ~ accumulate
        end
        obs = DataFrame(time = [0, 1]u"hr", b = [missing, 2.0])
        before = copy(obs)
        parameters = :SCalibrateAlignment => :a => (0.0, 4.0)
        optim = (; MaxSteps = 4, PopulationSize = 6, TraceMode = :silent)
        metric(E, O) = begin
            @test O == [2.0]
            Cropbox.metricfunc(:rmse)(E, O)
        end
        p = calibrate(SCalibrateAlignment, obs; target = :b, stop = 1, parameters, metric, optim)
        @test 0 <= p[:SCalibrateAlignment][:a] <= 4
        @test isequal(obs, before)
        @test_throws ArgumentError calibrate(SCalibrateAlignment, obs[1:1, :]; target = :b, stop = 1, parameters, optim)
        @test_throws ArgumentError calibrate(SCalibrateAlignment, obs; target = :b, stop = 0, snap = true,
            parameters, optim, metric = (E, O) -> 0.0)
        @test_throws ArgumentError calibrate(SCalibrateAlignment, obs; target = :b, stop = 1, snap = false, parameters, optim)
    end
end
