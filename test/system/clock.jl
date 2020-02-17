@testset "clock" begin
    @testset "basic" begin
        @system SClock(Controller)
        s = instance(SClock)
        # after one advance! in instance()
        @test s.context.clock.tick' == 1u"hr"
        update!(s)
        @test s.context.clock.tick' == 2u"hr"
    end

    @testset "config" begin
        @system SClockConfig(Controller)
        o = :Clock => (#=:init => 5,=# :step => 10)
        s = instance(SClockConfig; config=o)
        # after one advance! in instance()
        @test s.context.clock.tick' == 10u"hr"
        update!(s)
        @test s.context.clock.tick' == 20u"hr"
    end
end
