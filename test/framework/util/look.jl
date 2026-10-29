@testset "look" begin
    "System doc."
    @system SLookRegression(Controller) begin
        "Variable doc."
        a: amount => 1 ~ preserve(parameter)
        θ(a) => (a < 3 ? a : 0) ~ track
    end
    s = instance(SLookRegression; config=SLookRegression => :a => 2)
    source = "θ = 1\n    x = \"<tag>&\"\n"

    renderlook(args...; mime=MIME("text/plain"), color=false, kw...) = sprint(
        io -> look(io, mime, args...; kw...);
        context=:color => color,
    )
    stripansi(text) = replace(text, r"\e\[[0-9;]*m" => "")
    capturestdout(f) = mktemp() do _, io
        redirect_stdout(io) do
            f()
        end
        flush(io)
        seekstart(io)
        read(io, String)
    end

    @testset "system and variable inspection" begin
        system_type = renderlook(SLookRegression)
        @test occursin("[doc]", system_type)
        @test occursin("System doc.", system_type)
        @test occursin("[system]", system_type)
        @test occursin("SLookRegression", system_type)
        @test occursin("a (amount)", system_type)
        @test !occursin("a (amount) =", system_type)

        system_instance = renderlook(s)
        @test occursin("a (amount) = 2.0", system_instance)
        @test occursin("θ = 2.0", system_instance)
        @test renderlook(SLookRegression; doc=false, system=false) == ""
        @test !occursin("[doc]", renderlook(SLookRegression; doc=false))
        @test !occursin("[system]", renderlook(SLookRegression; system=false))

        variable_type = renderlook(SLookRegression, :a)
        @test occursin("Variable doc.", variable_type)
        @test occursin("[code]", variable_type)
        @test occursin("preserve(parameter)", variable_type)
        @test !occursin("[value]", variable_type)
        @test renderlook(SLookRegression, :amount) == variable_type

        variable_instance = renderlook(s, :a)
        @test occursin("[doc]", variable_instance)
        @test occursin("[code]", variable_instance)
        @test endswith(variable_instance, "[value]\n2.0")
        @test renderlook(s, :amount) == variable_instance
        @test renderlook(s, :a; value=false) == variable_type
        @test renderlook(s, :a; header=false, doc=false, code=false) == "2.0"
        @test renderlook(s, :a; doc=false, code=false, value=false) == ""
        @test !occursin("[doc]", renderlook(s, :a; doc=false))
        @test !occursin("[code]", renderlook(s, :a; code=false))
        @test !occursin("[", renderlook(s, :a; header=false))
    end

    @testset "macro inspection" begin
        @test stripansi(capturestdout(() -> (@look SLookRegression))) == renderlook(SLookRegression)
        @test stripansi(capturestdout(() -> (@look s.a))) == renderlook(s, :a)
        @test stripansi(capturestdout(() -> (@look s amount))) == renderlook(s, :amount)
    end

    @testset "terminal color" begin
        for args in ((SLookRegression,), (s,), (SLookRegression, :a), (s, :a), (s, :θ))
            plain = renderlook(args...)
            colored = renderlook(args...; color=true)
            @test !occursin("\e[", plain)
            @test occursin("\e[", colored)
            @test stripansi(colored) == plain
            @test !occursin(r"\[(?:operator|keyword|variable|number|string):", plain)
        end

        plain = sprint(io -> Cropbox.highlightcode(io, MIME("text/plain"), source); context=:color => false)
        colored = sprint(io -> Cropbox.highlightcode(io, MIME("text/plain"), source); context=:color => true)
        @test plain == source
        @test stripansi(colored) == source
        @test occursin("\e[", colored)

        name_plain = sprint(io -> Cropbox.highlightcode(io, MIME("text/plain"), "plain_name"); context=:color => false)
        name_colored = sprint(io -> Cropbox.highlightcode(io, MIME("text/plain"), "plain_name"); context=:color => true)
        @test name_plain == "plain_name"
        @test stripansi(name_colored) == name_plain
    end

    @testset "HTML output" begin
        font = "style=\"font-family: 'Fira Code'; font-size: x-small\""
        html = renderlook(s, :θ; mime=MIME("text/html"), header=false, value=false)
        @test occursin("<pre $font>", html)
        @test occursin("https://cdn.jsdelivr.net/gh/tonsky/FiraCode@4/distr/fira_code.css", html)
        @test occursin("&lt;", html)
        @test occursin("&gt;", html)
        @test occursin("θ", html)
        @test !occursin("a < 3", html)
        @test !occursin("\e[", html)

        # Notebook HTML must not inherit ANSI header coloring from the outer IO.
        variable_html = renderlook(s, :a; mime=MIME("text/html"), color=true, value=false)
        @test occursin("[doc]", variable_html)
        @test occursin("[code]", variable_html)
        @test !occursin("[value]", variable_html)
        @test !occursin("\e[", variable_html)
        @test !occursin("\e[", renderlook(s; mime=MIME("text/html"), color=true))

        system_html = renderlook(s; mime=MIME("text/html"), header=false, doc=false)
        @test occursin("<table", system_html)
        @test occursin("SLookRegression", system_html)
        @test occursin("(amount)", system_html)
        @test occursin("2.0", system_html)
        @test occursin("θ", system_html)

        mktempdir() do dir
            path = joinpath(dir, "code.html")
            Cropbox.writecodehtml(path, source)
            file_html = read(path, String)
            @test occursin(r"<span(?:\s|>)", file_html)
            @test occursin("<pre $font>", file_html)
            @test endswith(file_html, "</pre>")
            @test occursin("\n    ", file_html)
            @test occursin("&lt;tag&gt;", file_html)
            @test occursin("&amp;", file_html)
            @test occursin("θ", file_html)
            @test !occursin("<tag>", file_html)
            @test !occursin("\e[", file_html)

            rendered = sprint(io -> Cropbox.highlightcode(io, MIME("text/html"), source))
            @test file_html == rendered
        end
    end
end
