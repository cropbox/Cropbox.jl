using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    @system S(Controller) begin
        a => 1 ~ preserve
        b(a) ~ track
        c(b) ~ accumulate
    end
    c = @config

    @compile_workload begin
        let x, g0, g1, gb, A, Cs, RH
            Symbolics.@variables x g0 g1 gb A Cs RH
            Q = genpolynomialcoeffs((x-RH)*gb - (1-x)*(g0+g1*A*x/Cs), x)
            genpolynomialbody(Q; U=:(u"NoUnits"), lower=-Inf, upper=Inf, pick=:maximum)
        end
        r = simulate(S, config=c)
        simulate(S, configs=[c])
        visualize(r, :time, :c; backend=:UnicodePlots)
        visualize(r, :time, :c; backend=:Gadfly)[] #|> Cropbox.Gadfly.SVGJS()
        visualize(r, :time, :c; kind=:line, backend=:Gadfly)' #|> Cropbox.Gadfly.SVG()
        visualize(S, :time, :c; backend=:UnicodePlots)
        visualize(S, :time, :c; backend=:Gadfly)[] #|> Cropbox.Gadfly.SVGJS()
        #visualize(S, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.PDF()
        #visualize(S, :time, :c; backend=:Gadfly)[] |> Cropbox.Gadfly.PNG()
        #r |> display
        #display(MIME("text/html"), r)
    end
end
