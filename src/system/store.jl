import DataFrames: DataFrame, DataFrameRow, DataFrames
import CSV

@system DataFrameStore begin
    filename => "" ~ preserve::String(parameter)
    indexkey => :timestamp ~ preserve::Symbol(optional, parameter)

    i(t=nounit(context.clock.tick)): index => t + 1 ~ track::Int
    t(; r::DataFrameRow): timestamp => DataFrames.row(r) ~ call

    df(filename, indexkey, t): dataframe => begin
        df = CSV.read(filename)
        if !isnothing(indexkey)
            df[!, indexkey] = map(t, eachrow(df))
        end
        df
    end ~ preserve::DataFrame(extern, parameter)

    s(df, indexkey, i): store => begin
        if !isnothing(indexkey)
            df[df[!, indexkey] .== i, :][1, :]
        else
            df[i, :]
        end
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
