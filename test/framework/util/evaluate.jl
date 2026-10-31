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
