#TODO: implement proper tests (i.e. string comparison w/o color escapes)
@testset "graph" begin
    @testset "dependency" begin
        S = Cropbox.Context
        d = Cropbox.dependency(S)
        b = IOBuffer()
        show(b, MIME("text/plain"), d)
        ds = String(take!(b))
        @test ds == "[config → clock → context]"
        n = tempname()
        @test Cropbox.writesvg(n, d) == n*".svg"
    end

    @testset "hierarchy" begin
        S = Cropbox.Context
        h = Cropbox.hierarchy(S)
        b = IOBuffer()
        show(b, MIME("text/plain"), h)
        hs = String(take!(b))
        @test hs == "{Context, Clock}"
        n = tempname()
        @test Cropbox.writesvg(n, h) == n*".svg"
    end
end
