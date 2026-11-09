@enum ManipulateChoice first_choice second_choice

@testset "manipulate" begin
    B = Cropbox.Bonito
    serverconfig = B.SERVER_CONFIGURATION
    settings = map(x -> x[], serverconfig)
    page, subsession = B.CURRENT_SESSION[], B.FORCE_SUBSESSION_RENDERING[]
    assets = B.FORCED_ASSET_SERVER[]
    try
        B.force_asset_server!(B.NoServer)
        isolated = B.Session(B.NoConnection(); asset_server = B.NoServer())
        Cropbox.MANIPULATE_SESSIONS[isolated] = nothing
        for (port, proxy, expected) in ((9384, "", 0), (9390, "", 9390), (9384, "/proxy/9384", 9384))
            serverconfig.listen_port[], serverconfig.proxy_url[] = port, proxy
            manipulate(identity; parameters = ())
            session = B.Session(B.NoConnection(); asset_server = B.NoServer())
            B.CURRENT_SESSION[] = session
            @test isnothing(Cropbox.reset_manipulate())
            @test isnothing(B.CURRENT_SESSION[])
            @test session.status == B.CLOSED
            @test serverconfig.listen_port[] == expected
            @test serverconfig.proxy_url[] == proxy
        end
        @test isnothing(Cropbox.reset_manipulate())
        @test isolated.status == B.CLOSED
        @test isempty(Cropbox.MANIPULATE_SESSIONS)
        @test isnothing(B.GLOBAL_SERVER[])

        B.configure_server!(listen_port = 0)
        widget = Cropbox.ManipulateApp(manipulate(identity; parameters = ()))
        @test repr(widget) == "Cropbox interactive output"
        @test showable(MIME"text/html"(), widget)
        for _ in 1:2
            @test occursin(r"^<iframe\b[^>]*\bsrcdoc=", repr(MIME"text/html"(), widget))
        end
        sessions = collect(keys(Cropbox.MANIPULATE_SESSIONS))
        @test length(sessions) == 2
        Cropbox.reset_manipulate()
        @test all(s -> s.status == B.CLOSED, sessions)
    finally
        Cropbox.reset_manipulate()
        B.cleanup_globals()
        for (r, v) in zip(serverconfig, settings)
            r[] = v
        end
        B.CURRENT_SESSION[] = page
        B.force_subsession!(subsession)
        B.force_asset_server!(assets)
    end
    session = B.Session(B.NoConnection(); asset_server = B.NoServer())
    try
        w, o = Cropbox.manipulatewidget(session, (0:2)u"hr", 60u"minute", u"hr")
        @test w isa B.Slider
        @test o[] == 1
        w.index[] = 3
        @test o[] == 2
        @test Cropbox.manipulatewidget(session, 0:4, missing, nothing)[2][] == 2

        for (options, initial, expected) in (
            ([:a, :b], :a, :b),
            (ManipulateChoice, first_choice, second_choice),
            (Cropbox.OrderedDict("Low" => 1, "High" => 2), 1, 2),
        )
            w, o = Cropbox.manipulatewidget(session, options, initial, nothing)
            @test o[] == initial
            w.option_index[] = 2
            @test o[] == expected
        end
        w, o = Cropbox.manipulatewidget(session, false, true, nothing)
        @test o[] === true
        w.value[] = false
        @test o[] === false
        @test_throws ArgumentError Cropbox.manipulatewidget(session, Int[], missing, nothing)
        @test_throws ArgumentError Cropbox.manipulatewidget(session, [:a], :b, nothing)

        @system ManipulateTest(Controller) begin
            rate => 1 ~ preserve(parameter, u"g/hr")
            mass(rate) ~ accumulate(u"g")
            fixed => 3 ~ preserve(parameter)
        end
        seen = Config[]
        app = manipulate(c -> (push!(seen, c); c);
            parameters = ManipulateTest => :rate => 0:2,
            config = ManipulateTest => (:rate => 1, :fixed => 4))
        @test app isa B.App
        dom = app.handler(session, nothing)
        @test seen[end][:ManipulateTest][:rate] == 1u"g/hr"
        @test seen[end][:ManipulateTest][:fixed] == 4
        @test seen[end][:__manipulate__][Symbol("ManipulateTest.rate")] == 1u"g/hr"
        controls = B.children(first(B.children(dom)))
        slider = first(B.children(last(B.children(controls[2]))))
        slider.index[] = 3
        @test seen[end][:ManipulateTest][:rate] == 2u"g/hr"
        @test length(seen) == 2

        app = manipulate(identity; parameters = :0 => :rate => 0:0.1:5, config = :0 => :rate => 3.9)
        controls = B.children(first(B.children(app.handler(session, nothing))))
        defaultslider, readout = B.children(last(B.children(only(controls))))
        @test only(B.children(readout)) == "3.9"
        @test defaultslider.value[] ≈ 3.9

        for f in (Cropbox.deunitfy, identity, string, x -> DataFrame(rate = [x]), x -> HTML("<b>$x</b>"), _ -> nothing)
            app = manipulate(c -> f(c[:ManipulateTest][:rate]); parameters = ManipulateTest => :rate => 0:2)
            dom = app.handler(session, nothing)
            controls = B.children(first(B.children(dom)))
            w = first(B.children(last(B.children(controls[2]))))
            output = last(B.children(dom))
            for v in (0, 2)
                w.index[] = v + 1
                @test string(output[]) == string(f(v * u"g/hr"))
            end
        end

        plotapp = manipulate(ManipulateTest, :time, :mass;
            parameters = ManipulateTest => :rate => 0:2, stop = 2, backend = :Makie)
        p = last(B.children(plotapp.handler(session, nothing)))[]
        @test p isa Cropbox.Plot
        @test occursin("image/svg+xml", repr(MIME"text/html"(), B.jsrender(session, p)))
        close(session)
        slider.index[] = 1
        @test length(seen) == 2
    finally
        close(session)
    end
end
