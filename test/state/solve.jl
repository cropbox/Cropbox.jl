@testset "solve" begin
    @testset "basic" begin
        @system SSolve(Controller) begin
            a ~ preserve(parameter)
            b ~ preserve(parameter)
            c ~ preserve(parameter)
            x(x, a, b, c) => begin
                a*x^2 + b*x + c
            end ~ solve
        end
        s1 = instance(SSolve, config=:SSolve => (a=1, b=2, c=1))
        @test s1.x' == -1
        s2 = instance(SSolve, config=:SSolve => (a=1, b=-2, c=1))
        @test s2.x' == 1
        s3 = instance(SSolve, config=:SSolve => (a=1, b=2, c=-3))
        @test s3.x' == 1
        s4 = instance(SSolve, config=:SSolve => (a=1, b=-2, c=-3))
        @test s4.x' == 3
    end
end
