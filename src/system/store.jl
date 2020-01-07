import DataFrames: DataFrame, DataFrameRow, DataFrames
import CSV

@system DataFrameStore begin
    filename => "" ~ preserve::String(parameter)
    indexkey => :timestamp ~ preserve::Symbol(optional, parameter)

    index(t=nounit(context.clock.tick)) => t + 1 ~ track::Int
    timestamp(; r::DataFrameRow) => getfield(r, :row) ~ call

    dataframe(filename, indexkey, timestamp): df => begin
        df = CSV.read(filename)
        if !isnothing(indexkey)
            df[!, indexkey] = map(timestamp, eachrow(df))
        end
        df
    end ~ preserve::DataFrame(extern, parameter)

    store(df, indexkey, index): s => begin
        if !isnothing(indexkey)
            df[df[!, indexkey] .== index, :][1, :]
        else
            df[index, :]
        end
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
