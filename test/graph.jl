#TODO: implement proper tests (i.e. string comparison w/o color escapes)
@testset "graph" begin
    @testset "dependency" begin
        S = Cropbox.Context
        d = Cropbox.dependency(S)
        @test d isa Cropbox.Dependency
        n = tempname()
        @test Cropbox.writesvg(n, d) == n*".svg"
    end

    @testset "hierarchy" begin
        S = Cropbox.Context
        h = Cropbox.hierarchy(S)
        @test h isa Cropbox.Hierarchy
        n = tempname()
        @test Cropbox.writesvg(n, h) == n*".svg"
    end
end
