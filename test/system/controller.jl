@testset "controller" begin
    @testset "options" begin
        @system SControllerOptions(Controller) begin
            a ~ preserve(extern)
            b ~ ::Int(override)
        end
        o = (a=1, b=2)
        s = instance(SControllerOptions; options=o)
        @test s.a' == 1
        @test s.b == 2
    end

    @testset "config placeholder" begin
        @system SControllerConfigPlaceholder(Controller) begin
            a => 1 ~ preserve(parameter)
        end
        o = 0 => :a => 2
        s = instance(SControllerConfigPlaceholder; config=o)
        @test s.a' == 2
    end
end
