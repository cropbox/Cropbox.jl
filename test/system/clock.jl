@testset "clock" begin
    @testset "basic" begin
        @system SClock(Controller)
        s = instance(SClock)
        @test s.context.clock.tick' == 0u"hr"
        update!(s)
        @test s.context.clock.tick' == 1u"hr"
        update!(s)
        @test s.context.clock.tick' == 2u"hr"
    end

    @testset "config" begin
        @system SClockConfig(Controller)
        o = :Clock => (#=:init => 5,=# :step => 10)
        s = instance(SClockConfig; config=o)
        @test s.context.clock.tick' == 0u"hr"
        update!(s)
        @test s.context.clock.tick' == 10u"hr"
        update!(s)
        @test s.context.clock.tick' == 20u"hr"
    end
end
