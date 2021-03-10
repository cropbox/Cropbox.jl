@testset "core" begin
    @testset "not" begin
        @system SStateNot(Controller) begin
            f => false ~ preserve::Bool
            a(f) ~ flag
            b(!f) ~ flag
        end
        s = instance(SStateNot)
        @test s.a' == false && s.b' == true
    end
end
