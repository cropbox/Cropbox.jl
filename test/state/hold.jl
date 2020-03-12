@testset "flag" begin
    @testset "hold" begin
        @system SHold(Controller) begin
            a ~ hold
        end
        @test_throws ErrorException instance(SHold)
    end
end
