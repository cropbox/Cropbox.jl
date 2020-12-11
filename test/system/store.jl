using CSV
using DataFrames: DataFrames, DataFrame
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
            a(s) ~ drive
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
