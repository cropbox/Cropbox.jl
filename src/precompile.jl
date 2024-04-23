using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    @system S(Controller) begin
        a => 1 ~ preserve
        b(a) ~ track
        c(b) ~ accumulate
    end
    c = @config

    @compile_workload begin
        r = simulate(S, config=c)
        simulate(S, configs=[c])
        visualize(r, :time, :c; backend=:UnicodePlots)
        visualize(r, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS()
        visualize(r, :time, :c; kind=:line, backend=:Gadfly)' |> Cropbox.Gadfly.SVG()
        visualize(S, :time, :c; backend=:UnicodePlots)
        visualize(S, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.SVGJS()
        r |> display
        display(MIME("text/html"), r)
    end
end
