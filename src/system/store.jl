import DataFrames: DataFrame, DataFrameRow, DataFrames
import CSV

@system DataFrameStore begin
    filename => "" ~ preserve::String(parameter)
    ik: indexkey => :index ~ preserve::Symbol(parameter)

    i(t=nounit(context.clock.tick)): index => t + 1 ~ track::Int
    ix(; r::DataFrameRow): indexer => DataFrames.row(r) ~ call

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
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
