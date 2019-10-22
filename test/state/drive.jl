using DataFrames

@testset "drive" begin
    @testset "dict" begin
        @system SDriveDict(Controller) begin
            a(t=context.clock.tick) => Dict(:a => 10t) ~ drive(u"hr")
        end
        s = instance(SDriveDict)
        @test s.context.clock.tick == 1u"hr" && s.a == 10u"hr"
        update!(s)
        @test s.context.clock.tick == 2u"hr" && s.a == 20u"hr"
    end

    @testset "key" begin
        @system SDriveKey(Controller) begin
            a => Dict(:b => 1) ~ drive(key=:b)
        end
        s = instance(SDriveKey)
        @test s.a == 1
    end

    @testset "dataframe" begin
        @system SDriveDataFrame(Controller) begin
            df => DataFrame(t=(0:4)u"hr", a=0:10:40) ~ preserve::DataFrame
            a(df, t=context.clock.tick) => df[df.t .== t, :][1, :] ~ drive
        end
        s = instance(SDriveDataFrame)
        @test s.context.clock.tick == 1u"hr" && s.a == 10
        update!(s)
        @test s.context.clock.tick == 2u"hr" && s.a == 20
    end
end
