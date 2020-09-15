@testset "integrate" begin
    @testset "basic" begin
        @system SIntegrate(Controller) begin
            w => 1 ~ preserve(parameter)
            a => 0 ~ preserve(parameter)
            b => π ~ preserve(parameter)
            f(w; x) => w*sin(x) ~ integrate(from=a, to=b)
        end
        s1 = instance(SIntegrate)
        @test s1.f' == 2
        s2 = instance(SIntegrate, config=:0 => :w => 2)
        @test s2.f' == 4
        s3 = instance(SIntegrate, config=:0 => :a => π/2)
        @test s3.f' == 1
        s4 = instance(SIntegrate, config=:0 => (a = π, b = 2π))
        @test s4.f' == -2
    end
end
