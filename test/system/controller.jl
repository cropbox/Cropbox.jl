@testset "controller" begin
    @testset "config placeholder" begin
        @system SControllerConfigPlaceholder(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = 0 => :a => 2
        s = instance(SControllerConfigPlaceholder; config=o)
        @test s.a' == 2
    end
end
