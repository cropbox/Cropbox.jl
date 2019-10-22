@testset "flag" begin
    @testset "basic" begin
        @system SFlag(Controller) begin
            a => true ~ flag
            b => false ~ flag
        end
        s = instance(SFlag)
        @test s.a == true && s.b == false
    end
end
