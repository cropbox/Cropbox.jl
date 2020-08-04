import DataFrames: DataFrames, DataFrame
import TypedTables: TypedTables, Table

@testset "store" begin
    @testset "dataframe" begin
        @system SStoreDataFrame(DataFrameStore, Controller) begin
            a(s) => s[:a] ~ track::Int
            b(s) => s[:b] ~ track
        end
        a = [1, 2, 3]
        b = [4.0, 5.0, 6.0]
        df = DataFrame(a=a, b=b)
        n = DataFrames.nrow(df)
        r = simulate(SStoreDataFrame, config=:0 => (:df => df, :ik => :a), stop=n-1)
        @test r.a == a
        @test r.b == b
    end

    @testset "table" begin
        @system SStoreTable(TableStore, Controller) begin
            a(s) => s[:a] ~ track::Int
            b(s) => s[:b] ~ track
        end
        a = [1, 2, 3]
        b = [4.0, 5.0, 6.0]
        tb = Table(a=a, b=b)
        n = length(tb)
        r = simulate(SStoreTable, config=:0 => :tb => tb, stop=n-1)
        @test r.a == a
        @test r.b == b
    end
end
