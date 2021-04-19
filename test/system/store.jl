using DataFrames: DataFrames, DataFrame
using Dates: Dates, Date
using TimeZones
using TypedTables: TypedTables, Table

@testset "store" begin
    @testset "dataframe" begin
        @system SStoreDataFrame(DataFrameStore, Controller) begin
            a(s) => s[:a] ~ track::Int
            b(s) => s[:b] ~ track
        end
        a = [1, 2, 3]
        b = [4.0, 5.0, 6.0]
        df = DataFrame(; a, b)
        n = DataFrames.nrow(df)
        r = simulate(SStoreDataFrame, config=:0 => (:df => df, :ik => :a), stop=n-1)
        @test r.a == a
        @test r.b == b
    end

    @testset "day" begin
        @system SStoreDay(DayStore, Controller) begin
            a(s) => s.a ~ track
        end
        r = mktemp() do f, io
            write(io, "day (d),a\n0,0\n1,10\n2,20")
            close(io)
            c = (:Clock => :step => 1u"d", :0 => :filename => f)
            simulate(SStoreDay, config=c, stop=2)
        end
        @test r.a[1] == 0
        @test r.a[2] == 10
        @test r.a[end] == 20
    end

    @testset "date" begin
        @system SStoreDate(DateStore, Controller) begin
            a(s) => s.a ~ track
        end
        r = mktemp() do f, io
            write(io, "date (:Date),a\n2020-12-09,0\n2020-12-10,10\n2020-12-11,20")
            close(io)
            config = (
                :Clock => :step => 1u"d",
                :Calendar => :init => ZonedDateTime(2020, 12, 9, tz"UTC"),
                :0 => :filename => f,
            )
            simulate(SStoreDate; config, stop=2u"d")
        end
        @test r.a[1] == 0
        @test r.a[2] == 10
        @test r.a[end] == 20
    end

    @testset "time" begin
        @system SStoreTime(TimeStore, Controller) begin
            a(s) => s.a ~ track
        end
        r = mktemp() do f, io
            write(io, "date (:Date),time (:Time),a\n2020-11-15,01:00,0\n2020-11-15,02:00,10\n2020-11-15,03:00,20")
            close(io)
            config = (
                :Clock => :step => 1u"hr",
                :Calendar => :init => ZonedDateTime(2020, 11, 15, 1, tz"America/Los_Angeles"),
                :0 => (:filename => f, :tz => tz"America/Los_Angeles"),
            )
            simulate(SStoreTime; config, stop=2u"hr")
        end
        @test r.a[1] == 0
        @test r.a[2] == 10
        @test r.a[end] == 20
    end

    @testset "table" begin
        @system SStoreTable(TableStore, Controller) begin
            a(s) => s[:a] ~ track::Int
            b(s) => s[:b] ~ track
        end
        a = [1, 2, 3]
        b = [4.0, 5.0, 6.0]
        tb = Table(; a, b)
        n = length(tb)
        r = simulate(SStoreTable, config=:0 => :tb => tb, stop=n-1)
        @test r.a == a
        @test r.b == b
    end
end
