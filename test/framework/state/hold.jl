@testset "hold" begin
    @testset "basic" begin
        @system SHold(Controller) begin
            a ~ hold
        end
        @test_throws ErrorException instance(SHold)
    end
end
