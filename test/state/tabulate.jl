@testset "tabulate" begin
    @testset "basic" begin
        @system STabulate(Controller) begin
            T => [
                # a b
                  0 3 ; # A
                  1 4 ; # B
                  2 5 ; # C
            ] ~ tabulate(rows=(:A, :B, :C), columns=(:a, :b))
            p(T; c::Symbol, r::Symbol) => T[c][r] ~ call
            Aa(p) => p(:A, :a) ~ track
            Ba(p) => p(:B, :a) ~ track
            Ca(p) => p(:C, :a) ~ track
            Ab(p) => p(:A, :b) ~ track
            Bb(p) => p(:B, :b) ~ track
            Cb(p) => p(:C, :b) ~ track
        end
        s = instance(STabulate)
        @test s.Aa' == 0
        @test s.Ba' == 1
        @test s.Ca' == 2
        @test s.Ab' == 3
        @test s.Bb' == 4
        @test s.Cb' == 5
    end
end
