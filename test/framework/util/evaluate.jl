using DataFrames

@testset "evaluate" begin
    @testset "two-table metric order" begin
        observed = [10.0, 20.0, 40.0]
        estimated = [12.0, 18.0, 44.0]
        obs = DataFrame(time=1:3, mass=observed)
        est = DataFrame(time=1:3, mass=estimated)

        metric(E, O) = begin
            @test E == estimated
            @test O == observed
            sum(E .- O)
        end
        @test evaluate(obs, est; index=:time, target=:mass, metric) == 4.0
        @test evaluate(obs, est; target = :mass, metric) == 4.0

        # Symmetric errors do not reveal a reversal; these denominators do.
        expected = (
            rmse=sqrt(8),
            nrmse=sqrt(8) / (70/3),
            rmspe=sqrt(0.02),
            mae=8/3,
            mape=0.4/3,
            ef=166/175,
            dr=22/25,
        )
        for (metric, score) in pairs(expected)
            @test evaluate(obs, est; index=:time, target=:mass, metric) ≈ score
        end

        mapped = rename(est, :mass => :predicted)
        @test evaluate(obs, mapped; index=:time, target=:mass=>:predicted,
            metric=(E, O) -> sum(E .- O)) == 4.0

        obs_multi = DataFrame(time=1:3, mass=observed, other=observed)
        est_multi = DataFrame(time=1:3, predicted=estimated, other=[8.0, 22.0, 36.0])
        @test evaluate(obs_multi, est_multi; index=:time,
            target=[:mass=>:predicted, :other],
            metric=(E, O) -> sum(E .- O)) == (4.0, -4.0)
    end

    @testset "joined rows, missing values, and units" begin
        obs = DataFrame(time=1:4, mass=[10.0, missing, 40.0, 50.0])
        est = DataFrame(time=[4, 3, 1, 2, 5], predicted=[missing, 44.0, 12.0, 18.0, 999.0])
        metric(E, O) = begin
            @test sort(collect(zip(E, O))) == [(12.0, 10.0), (44.0, 40.0)]
            sum(E .- O)
        end
        @test evaluate(obs, est; index=:time, target=:mass=>:predicted, metric) == 6.0

        obs_units = DataFrame(time=[1, 2]u"hr", mass=[10, 20]u"g")
        est_units = DataFrame(time=[2, 1]u"hr", predicted=[0.022, 0.011]u"kg")
        @test evaluate(obs_units, est_units; index=:time, target=:mass=>:predicted,
            metric=(E, O) -> sum(E .- O)) ≈ 3u"g"
        @test evaluate(obs_units, est_units; index=:time, target=:mass=>:predicted,
            metric=:rmse) ≈ sqrt(2.5)u"g"

        # Missing pairs are dropped, but a non-finite prediction stays visible.
        obs_nan = DataFrame(time=[1], mass=[10.0])
        est_nan = DataFrame(time=[1], mass=[NaN])
        @test isnan(evaluate(obs_nan, est_nan; index=:time, target=:mass))
    end

    @testset "index alignment and input preservation" begin
        obs = DataFrame(hour = [1, 2, 3]u"hr", mass = [10.0, 20.0, 30.0], note = fill("observed", 3))
        est = DataFrame(time = [180, 60, 240]u"minute", predicted = [33.0, 11.0, 999.0], note = fill("estimated", 3))
        before = copy(obs), copy(est)
        target = :mass => :predicted
        for index in (:hour => :time, "hour" => "time")
            @test evaluate(obs, est; index, target, metric = :mae) == 2.0
            @test evaluate(view(obs, :, :), view(est, :, :); index, target, metric = :mae) == 2.0
        end
        @test evaluate(rename(obs, :hour => :time), est; target, metric = :mae) == 2.0
        @test isequal((obs, est), before)

        o = DataFrame(site = [1, 2], time = [1, 1]u"hr", mass = [10.0, 20.0])
        e = DataFrame(site = [2, 1], t = [60, 60]u"minute", mass = [22.0, 11.0])
        @test evaluate(o, e; index = [:site, :time => :t], target = :mass, metric = :mae) == 1.5
    end

    @testset "complete matching rows" begin
        obs = DataFrame(time = 1:3, a = [1, 2, 3], b = [10, missing, 30])
        est = DataFrame(time = 1:3, a = [2, 100, 5], b = [11, 22, 33])
        @test evaluate(obs, est; target = [:a, :b], metric = (E, O) -> sum(E .- O)) == (3, 4)
        @test_throws ArgumentError evaluate(obs, est[1:0, :]; target = :a)
        @test_throws ArgumentError evaluate(obs[1:1, :], est[3:3, :]; target = :a)
        @test_throws ArgumentError evaluate(obs[2:2, :], est; target = :b)
    end

    @testset "target types" begin
        T = Cropbox.TimeZones
        t = T.ZonedDateTime(2026, 1, 1, T.TimeZone("UTC"))
        obs = DataFrame(time = [1], event = [t])
        est = DataFrame(time = [1], event = [T.astimezone(t, T.TimeZone("Asia/Seoul"))])
        @test evaluate(obs, est; target = :event, metric = (E, O) -> only(E) - only(O)) == Cropbox.Dates.Millisecond(0)
    end

    @testset "system and two-table agreement" begin
        @system SEvaluateMetricOrder(Controller) begin
            rate => 11 ~ preserve(parameter)
            mass(rate) ~ accumulate
        end
        est = simulate(SEvaluateMetricOrder; stop=3, target=:mass, verbose=false)
        obs = DataFrame(time=est.time[2:end], mass=[10.0, 20.0, 30.0])
        signed_error(E, O) = sum(E .- O)
        for metric in (:rmse, :nrmse, :rmspe, :mae, :mape, :ef, :dr, signed_error)
            system_score = evaluate(SEvaluateMetricOrder, obs;
                target=:mass, stop=3, metric, verbose=false)
            table_score = evaluate(obs, est; index=:time, target=:mass, metric)
            @test table_score ≈ system_score
        end

        incomplete = DataFrame(time = obs.time, mass = [10.0, missing, 30.0])
        @test evaluate(SEvaluateMetricOrder, incomplete; target = :mass, stop = 3) ≈
            evaluate(incomplete, est; target = :mass)
        @test_throws ArgumentError evaluate(SEvaluateMetricOrder, incomplete[2:2, :]; target = :mass, stop = 3)
        @test_throws ArgumentError evaluate(SEvaluateMetricOrder, obs; target = :mass, stop = 0, snap = true, metric = signed_error)
        @test_throws ArgumentError evaluate(SEvaluateMetricOrder, obs; target = :mass, stop = 3, snap = false)

        snap(s) = s.context.clock.time' == 1u"hr"
        @test evaluate(SEvaluateMetricOrder, obs; target = :mass, stop = 3, snap) == 1.0
    end

    @testset "floating-point time index" begin
        @system SEvaluateTimeIndex(Controller) begin
            a => 1 ~ accumulate
        end
        obs = DataFrame(time=[0.1]u"hr", a=[0.1])
        e = evaluate(
            SEvaluateTimeIndex,
            obs;
            config=:Clock => (:step => 6u"minute"),
            target=:a,
            stop=(1//10)u"hr",
            verbose=false,
        )
        @test e === 0.0
    end
end
