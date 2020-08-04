import DataFrames: DataFrames, DataFrame
import CSV

@system StoreBase begin
    filename => "" ~ preserve::String(parameter)
    ik: indexkey => :index ~ preserve::Symbol(parameter)

    i(t=nounit(context.clock.tick)): index => t + 1 ~ track::Int
    ix: indexer ~ hold

    s: store ~ hold
end

@system DataFrameStore(StoreBase) begin
    ix(; r::DataFrames.DataFrameRow): indexer => DataFrames.row(r) ~ call::Int

    df(filename, ik, ix): dataframe => begin
        df = CSV.read(filename)
        df[!, ik] = map(ix, eachrow(df))
        df
    end ~ preserve::DataFrame(extern, parameter)

    gdf(df, ik): grouped_dataframe => begin
        DataFrames.groupby(df, ik)
    end ~ preserve::DataFrames.GroupedDataFrame{DataFrame}

    s(gdf, i): store => begin
        gdf[(i,)][1, :]
    end ~ track::DataFrames.DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
