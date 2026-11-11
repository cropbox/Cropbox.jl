@system GraphStyleExample begin
    p => 1 ~ preserve(parameter)
    x(p) => p + 1 ~ track
    total(x) ~ accumulate
    done(x) => x > 2 ~ flag
end

@system GraphEdgeStyleExample begin
    lower => 0 ~ preserve
    upper => 2 ~ preserve
    root(root) => root - 1 ~ bisect(lower=lower, upper=upper)
end

@system GraphParameterExample begin
    source    => 1      ~ preserve
    p(source) => source ~ preserve(parameter)
end

@system GraphSelectionExample begin
    a: input => 1 ~ preserve(parameter)
    b(a) => 2a ~ track
    c(b) => b + 1 ~ track
    d(c) => 2c ~ track
    e(d) => d + 1 ~ track
    side(a) => -a ~ track
end

@system GraphInspectionOnly begin
    x => error("structure inspection must not execute a variable") ~ track
end

@system GraphExecutionExample(Controller) begin
    rate => 2 ~ preserve(parameter, u"g/hr")
    mass(rate) ~ accumulate(u"g")
end

@system GraphLanguageExample begin
    source ~ hold
end

@system GraphTemporalExample begin
    rate => 1 ~ preserve
    mass(rate) ~ accumulate
    output(mass) => mass ~ track
end

@testset "graph" begin
    varnames(d) = Set(n.info.name for n in d.N)

    @testset "structure" begin
        @test visualize(GraphInspectionOnly) isa Cropbox.Dependency
        @test visualize(GraphInspectionOnly; kind=:hierarchy) isa Cropbox.Hierarchy
        @test varnames(visualize(GraphStyleExample)) == varnames(Cropbox.dependency(GraphStyleExample))
        @test repr(MIME("text/plain"), visualize(Cropbox.Context)) ==
            "Dependency update order: [config, clock, context]"
        @test repr(MIME("text/plain"), visualize(Cropbox.Context; kind=:hierarchy)) == "{Context, Clock}"
        @test !haskey(visualize(GraphStyleExample; kind=:hierarchy).I, :Context)
        @test !Base.isexported(Cropbox, :dependency)
        @test !Base.isexported(Cropbox, :hierarchy)
        @test_throws ArgumentError visualize(GraphStyleExample; kind=:unknown)
        @test_throws ArgumentError visualize(GraphStyleExample, :total; kind=:hierarchy)

        @test simulate(GraphExecutionExample; stop=2u"hr", target=:mass).mass == [0, 2, 4]u"g"
        for backend in (:UnicodePlots, :Makie)
            p = visualize(GraphExecutionExample, :time, :mass; stop=2u"hr", kind=:line, backend)
            @test p isa Cropbox.Plot
            @test Cropbox.detectbackend(p) == backend
        end
    end

    @testset "selection" begin
        names(selector; kw...) = varnames(visualize(GraphStyleExample, selector; kw...))
        @test names(:total; depth=0) == Set((:total,))
        @test names(:total) == Set((:context, :x, :total))
        @test names(:total; depth=2) == Set((:config, :context, :p, :x, :total, :done))
        @test names(:x; direction=:up) == Set((:config, :p, :x))
        @test names(:x; direction=:down) == Set((:x, :total, :done))
        @test names(:x; direction=:both) == Set((:config, :p, :x, :total, :done))
        @test names([:total, :total]) == names(:total)
        @test names([:p, :x] => [:total, :done]) == Set((:config, :p, :x, :total, :done))
        @test count(n -> n.info.name == :total, visualize(GraphStyleExample, :total; depth=0).N) == 2

        parameter = visualize(GraphParameterExample, :p; depth=0)
        @test varnames(parameter) == Set((:config, :p))
        c = findfirst(n -> n.info.name == :config, parameter.N)
        p = findfirst(n -> n.info.name == :p, parameter.N)
        @test Cropbox.has_edge(parameter.g, c, p)
        @test !Cropbox.has_edge(parameter.g, p, c)

        neighborhood = visualize(GraphSelectionExample, [:a, :e])
        path = visualize(GraphSelectionExample, :a => :e)
        @test varnames(neighborhood) == Set((:config, :a, :b, :d, :e, :side))
        @test varnames(path) == Set((:config, :a, :b, :c, :d, :e))
        @test varnames(visualize(GraphSelectionExample, :input => :e)) == varnames(path)
        @test varnames(visualize(GraphSelectionExample, :a => :e; depth=0, direction=:down)) == varnames(path)
        @test varnames(visualize(GraphSelectionExample, [:a, :e]; depth=0)) == Set((:config, :a, :e))
        @test varnames(visualize(GraphSelectionExample, [:side, :a => :e]; depth=0)) ==
            union(varnames(path), Set((:side,)))
        @test varnames(visualize(GraphSelectionExample, [:a => :b, :d => :e])) == Set((:config, :a, :b, :d, :e))
        @test varnames(visualize(GraphSelectionExample, :a => :a)) == Set((:config, :a))
        @test visualize(GraphSelectionExample, :input; depth=0).focus == Set((:a,))
        @test path.focus == Set((:a, :e))
        @test_throws ArgumentError visualize(GraphSelectionExample, :side => :e)

        @test_throws ArgumentError visualize(GraphTemporalExample, :rate => :output)
        temporal = visualize(GraphTemporalExample, [:rate => :mass, :output]; direction=:up)
        @test varnames(temporal) == Set((:rate, :mass, :output))
        @test count(n -> n.info.name == :mass, temporal.N) == 2

        d = visualize(GraphStyleExample)
        before = (copy(d.g), copy(d.N), copy(d.I), copy(d.focus))
        Cropbox.selectiondependency(d, [:p => :total])
        Cropbox.makedot(d; style=(group=:system,))
        @test (d.g, d.N, d.I, d.focus) == before

        for selector in (:unknown, Symbol[], [:p, :unknown], :done => :p,
                         :unknown => :total, Symbol[] => :total, 1 => :total, [:total, 1])
            @test_throws ArgumentError visualize(GraphStyleExample, selector)
        end
        @test_throws ArgumentError visualize(GraphStyleExample, :total; depth=-1)
        @test_throws ArgumentError visualize(GraphStyleExample, :total; direction=:sideways)
    end

    @testset "output" begin
        label = Cropbox.graphlabel("<x>&\"\n"; bold=true, italic=true)
        @test Cropbox.dotvalue(label) == "<<B><I>&lt;x&gt;&amp;&quot;<BR/></I></B>>"
        @test Cropbox.dotvalue(Cropbox.graphlabel("\\N"; bold=true)) == "<<B>\\\\N</B>>"

        d = visualize(GraphStyleExample)
        h = visualize(GraphExecutionExample; kind=:hierarchy)
        language = visualize(GraphLanguageExample, :source; depth=0)
        loop = Cropbox.hierarchy()
        Cropbox.node!(loop, :Recursive)
        Cropbox.link!(loop, :Recursive, :Recursive)
        @test_throws ArgumentError Cropbox.makedot(d; style=(group=:unknown,))
        @test_throws ArgumentError Cropbox.makedot(d; style=(fontnme="Courier",))

        rendered = repr(MIME("image/svg+xml"), d)
        @test occursin("<svg", rendered) && !occursin("Graphviz rendering unavailable", rendered)
        fallback = IOBuffer()
        Cropbox._showsvg(fallback, d; engine=:unknown_engine)
        @test occursin("Graphviz rendering unavailable", String(take!(fallback)))

        mktempdir() do dir
            cases = (
                (d, ()),
                (d, (group=:system, rankdir=:LR)),
                (visualize(GraphSelectionExample, :input), (alias=true,)),
                (visualize(GraphEdgeStyleExample), ()),
                (language, ()),
                (language, (fontname="sans-serif", fontsize=10)),
                (h, ()),
                (loop, ()),
            )
            for (i, (g, style)) in enumerate(cases)
                svg = Cropbox.writeimage(joinpath(dir, "$i.svg"), g; style)
                @test occursin("<svg", read(svg, String))
            end
            dot = Cropbox.writedot(joinpath(dir, "dependency"), d)
            @test endswith(dot, ".dot") && occursin("digraph", read(dot, String))
            pdf = Cropbox.writeimage(joinpath(dir, "dependency.pdf"), d)
            @test read(pdf)[1:4] == collect(codeunits("%PDF"))
            base = joinpath(dir, "dependency")
            @test Cropbox.writeimage(base, d; format=:svg, engine=:neato) == base * ".svg"
            @test Cropbox.writeimage(base * ".pdf", d; format=:svg) == base * ".pdf.svg"
            @test_throws ErrorException Cropbox.writeimage(base * ".svg", d; engine=:unknown_engine)
        end
    end
end
