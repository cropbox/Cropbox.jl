using DataFrames

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
            a => 0 ~ preserve(parameter, u"m/hr")
            b(a) ~ accumulate(u"m")
        end
        n = 10
        t, a, b = 10.0u"hr", 20u"m/hr", 200u"m"
        #FIXME: parameter range units are just ignored
        A = [0.0, 100.0]u"m/hr"
        obs = DataFrame(time=[t], b=[b])
        p = calibrate(SCalibrateUnit, obs, stop=n, target=:b, parameters=("SCalibrateUnit.a" => A))
        @test p[:SCalibrateUnit][:a] == Cropbox.deunitfy(a)
        r = simulate(SCalibrateUnit, stop=n, config=p)
        @test r[r.time .== t, :][1, :b] == b
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
    end
end
