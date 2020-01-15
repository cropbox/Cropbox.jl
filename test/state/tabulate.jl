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

    @testset "parameter" begin
        @system STabulateParameter(Controller) begin
            T ~ tabulate(rows=(:A, :B, :C), columns=(:a, :b), parameter)
            p(T; c::Symbol, r::Symbol) => T[c][r] ~ call
            Aa(p) => p(:A, :a) ~ track
            Ba(p) => p(:B, :a) ~ track
            Ca(p) => p(:C, :a) ~ track
            Ab(p) => p(:A, :b) ~ track
            Bb(p) => p(:B, :b) ~ track
            Cb(p) => p(:C, :b) ~ track
        end
        o = STabulateParameter => :T => [
            # a b
              0 3 ; # A
              1 4 ; # B
              2 5 ; # C
        ]
        s = instance(STabulateParameter, config=o)
        @test s.Aa' == 0
        @test s.Ba' == 1
        @test s.Ca' == 2
        @test s.Ab' == 3
        @test s.Bb' == 4
        @test s.Cb' == 5
    end

    @testset "default columns" begin
        @system STabulateDefaultColumns(Controller) begin
            T => [
                # a b
                  0 2 ; # a
                  1 3 ; # b
            ] ~ tabulate(rows=(:a, :b))
            aa(T) => T[:a][:a] ~ track
            ba(T) => T[:b][:a] ~ track
            ab(T) => T[:a][:b] ~ track
            bb(T) => T[:b][:b] ~ track
        end
        s = instance(STabulateDefaultColumns)
        @test s.T.rows == s.T.columns == (:a, :b)
        @test s.aa' == 0
        @test s.ba' == 1
        @test s.ab' == 2
        @test s.bb' == 3
    end
end
