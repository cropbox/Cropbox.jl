using DataFrames

@testset "evaluate" begin
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
