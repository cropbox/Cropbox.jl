@testset "Makie" begin
    M = Cropbox.CairoMakie
    fontsize = M.Makie.theme(:fontsize)[]
    p = visualize([4, 0]u"hr", [4, 0]u"g"; backend = :Makie, kind = :line, name = "model", legendpos = (0.1, -0.3))
    ax = p.opt[:axis]
    @test Cropbox.detectbackend(p) == :Makie
    @test p[] isa M.Figure
    @test first.(ax.scene.plots[1][1][]) == [0, 4]
    @test visualize!(p, [0, 4]u"hr", [4, 0]u"g";
        kind = :scatterline, name = "reference", color = 1, linestyle = :dot) === p
    @test p.opt[:colors][1] == p.opt[:colors][2]
    @test p.opt[:labels] == ["model", "reference"]
    @test p.opt[:legendpos] == (0.1, -0.3)
    @test count(x -> x isa M.Legend, p[].content) == 1
    @test visualize!(p, 120u"minute", 2000u"mg", "An = 10\ngs = 0.2") === p
    @test ax.limits[] == ((0, 4), (0, 4))
    @test ax.xlabel[] == " (hr)"

    for kind in (:scatter, :step)
        q = visualize([0, 1, 2], [false, true, false]; backend = :Makie, kind, legend = false)
        @test isnothing(get(q.opt, :key, nothing))
        kind == :step && @test q.opt[:axis].yticks[] == (1:2, ["false", "true"])
    end
    @test visualize!(p, [1, 3]; kind = :hline) === p
    @test visualize!(p, [1, 3]; kind = :vline) === p

    for (kind, limits, unit) in (
        (:hline, (; xlim = (0, 4)), (; yunit = u"g")),
        (:vline, (; ylim = (0, 4)), (; xunit = u"g")),
    )
        q = visualize(2000u"mg"; backend = :Makie, kind, limits..., unit...)
        @test q.opt[:Xs] == [[2]]
        @test q.opt[kind == :hline ? :ylim : :xlim] == (1, 3)
    end

    cats = [2, 1]
    q = visualize([0, 1], [1, 2]; backend = :Makie, kind = :step, ycat = cats)
    @test visualize!(q, [0, 1], [2, 3]; kind = :step) === q
    @test q.opt[:axis].yticks[] == (1:3, ["2", "1", "3"])
    @test q.opt[:ycat] == [2, 1, 3]
    @test cats == [2, 1]
    @test last.(q.opt[:axis].scene.plots[1][1][]) == [2, 1]
    @test last.(q.opt[:axis].scene.plots[2][1][]) == [1, 3]

    dates = [DateTime(2020, 1, 1), DateTime(2020, 2, 1)]
    q = visualize(dates, [1, 2]; backend = :Makie, kind = :line)
    @test q.opt[:xlim] == Tuple(dates)
    @test first.(q.opt[:axis].scene.plots[1][1][]) == Dates.value.(dates)

    df = DataFrame(x = [2, 1, 2, 1], y = [2, 1, 1, 2], z = [5., 2., 4., 3.])
    @test_throws ArgumentError visualize(vcat(df, df), :x, :y, :z; backend = :Makie)
    for kind in (:heatmap, :contour)
        q = visualize(df, :x, :y, :z; backend = :Makie, kind, zlim = (0, 10), zgap = 2, zlabgap = 2)
        layer = first(q.opt[:axis].scene.plots)
        @test layer[3][] == [2 3; 4 5]
        @test Tuple(layer.colorrange[]) == (0, 10)
        @test length(filter(x -> x isa M.Colorbar, q[].content)) == 1
        if kind == :contour
            labels = last(q.opt[:axis].scene.plots)
            @test !isempty(labels.text_strings[])
            @test all(isfinite, labels.text_rotation[])
        end
        q = visualize(df, :x, :y, :z; backend = :Makie, kind, legend = false)
        @test !any(x -> x isa M.Colorbar, q[].content)
    end

    @test !ax.leftspinevisible[]
    @test M.Makie.theme(:fontsize)[] == fontsize
    @test showable(MIME"image/png"(), p)
    signature = b"\x89PNG\r\n\x1a\n"
    io = IOBuffer()
    show(io, MIME"image/png"(), p)
    @test take!(io)[1:8] == signature
    mktempdir() do dir
        for ext in ("png", "svg", "pdf")
            M.save(joinpath(dir, "plot.$ext"), p[])
        end
        @test read(joinpath(dir, "plot.png"), 8) == signature
        @test occursin("<svg", read(joinpath(dir, "plot.svg"), String))
        @test read(joinpath(dir, "plot.pdf"), 5) == b"%PDF-"
    end
end
