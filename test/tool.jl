using DataFrames

@testset "util" begin
    @testset "simulate" begin
        @system SSimulate(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        r = simulate(SSimulate, n)
        @test r isa DataFrame
        @test size(r, 1) == (n+1)
        @test names(r) == [:tick, :a, :b]
        @test r[end, :tick] == (n+1)u"hr"
        @test r[end, :a] == 1
        @test r[end, :b] == n
        r = simulate(SSimulate, n, config=(:SSimulate => :a => 2))
        @test r[end, :a] == 2
        @test r[end, :b] == 2n
        r = simulate(SSimulate, n, target=[:b])
        @test size(r, 2) == 2
        @test names(r) == [:tick, :b]
        r = simulate(SSimulate, n, index=:b, target=[:b])
        @test size(r, 2) == 1
        @test names(r) == [:b]
    end

    @testset "simulate with terminate" begin
        @system SSimulateTerminate(Controller) begin
            a => 1 ~ preserve(parameter)
            b(a) ~ accumulate
            z(b) => b >= 10 ~ flag
        end
        r = simulate(SSimulateTerminate, terminate="z")
        @test r[end, :b] == 10
        @test r[end-1, :b] != 10
    end

    @testset "calibrate" begin
        @system SCalibrate(Controller) begin
            a => 0 ~ preserve(parameter)
            b(a) ~ accumulate
        end
        n = 10
        t, a, b = 10.0u"hr", 20, 180
        A = (0.0, 100.0)
        obs = DataFrame(tick=[t], b=[b])
        p = calibrate(SCalibrate, obs, n, target=:b, parameters=("SCalibrate.a" => A))
        @test p[:SCalibrate][:a] == a
        r = simulate(SCalibrate, n, config=p)
        @test r[r[!, :tick] .== t, :][1, :b] == b
    end

    @testset "calibrate with unit" begin
        @system SCalibrateUnit(Controller) begin
            a => 0 ~ preserve(parameter, u"m/hr")
            b(a) ~ accumulate(u"m")
        end
        n = 10
        t, a, b = 10.0u"hr", 20u"m/hr", 180u"m"
        #FIXME: parameter range units are just ignored
        A = [0.0, 100.0]u"m/hr"
        obs = DataFrame(tick=[t], b=[b])
        p = calibrate(SCalibrateUnit, obs, n, target=:b, parameters=("SCalibrateUnit.a" => A))
        @test p[:SCalibrateUnit][:a] == ustrip(a)
        r = simulate(SCalibrateUnit, n, config=p)
        @test r[r[!, :tick] .== t, :][1, :b] == b
    end

    @testset "calibrate with config" begin
        @system SCalibrateConfig(Controller) begin
            a => 0 ~ preserve(parameter)
            w => 1 ~ preserve(parameter)
            b(a, w) => w*a ~ accumulate
        end
        n = 10
        t, a, b = 10.0u"hr", 20, 180
        w1, w2 = 1, 2
        A = (0.0, 100.0)
        obs = DataFrame(tick=[t], b=[b])
        params = ("SCalibrateConfig.a" => A)
        p1 = calibrate(SCalibrateConfig, obs, n, target=:b, config=(:SCalibrateConfig => :w => w1), parameters=params)
        @test p1[:SCalibrateConfig][:a] == a/w1
        p2 = calibrate(SCalibrateConfig, obs, n, target=:b, config=(:SCalibrateConfig => :w => w2), parameters=params)
        @test p2[:SCalibrateConfig][:a] == a/w2
    end
end
