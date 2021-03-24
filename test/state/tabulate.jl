@testset "tabulate" begin
    @testset "basic" begin
        @system STabulate(Controller) begin
            T => [
                # a b
                  0 4 ; # A
                  1 5 ; # B
                  2 6 ; # C
                  3 7 ; # D
            ] ~ tabulate(rows=(:A, :B, :C, :D), columns=(:a, :b))
            Aa(T) => T.A.a ~ preserve
            Ba(T) => T.B[:a] ~ preserve
            Ca(T) => T[:C].a ~ preserve
            Da(T) => T[:D][:a] ~ preserve
            Ab(T.A.b) ~ preserve
            Bb(T.B[:b]) ~ preserve
            Cb(T[:C].b) ~ preserve
            Db(T[:D][:b]) ~ preserve
        end
        s = instance(STabulate)
        @test s.Aa' == 0
        @test s.Ba' == 1
        @test s.Ca' == 2
        @test s.Da' == 3
        @test s.Ab' == 4
        @test s.Bb' == 5
        @test s.Cb' == 6
        @test s.Db' == 7
    end

    @testset "parameter" begin
        @system STabulateParameter(Controller) begin
            T ~ tabulate(rows=(:A, :B, :C), columns=(:a, :b), parameter)
            Aa(T.A.a) ~ preserve
            Ba(T.B.a) ~ preserve
            Ca(T.C.a) ~ preserve
            Ab(T.A.b) ~ preserve
            Bb(T.B.b) ~ preserve
            Cb(T.C.b) ~ preserve
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
            aa(T) => T.a.a ~ preserve
            ba(T) => T.b.a ~ preserve
            ab(T) => T.a.b ~ preserve
            bb(T) => T.b.b ~ preserve
        end
        s = instance(STabulateDefaultColumns)
        @test getfield(s.T, :rows) == getfield(s.T, :columns) == (:a, :b)
        @test s.aa' == 0
        @test s.ba' == 1
        @test s.ab' == 2
        @test s.bb' == 3
    end

    @testset "arg" begin
        @system STabulateArg(Controller) begin
            x => 0 ~ preserve(parameter)
            T(x) => [
                # a b
                  x   x+2 ; # A
                  x+1 x+3 ; # B
            ] ~ tabulate(rows=(:A, :B), columns=(:a, :b))
        end
        s = instance(STabulateArg)
        @test s.T.A.a == 0
        @test s.T.B.a == 1
        @test s.T.A.b == 2
        @test s.T.B.b == 3
    end
end
