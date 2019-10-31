using DataFrames
using CSV

@system DataFrameStore begin
    filename => "" ~ preserve::String(parameter)
    indexkey => :timestamp ~ preserve::Symbol(parameter)

    index ~ hold
    timestamp ~ hold

    dataframe(filename, indexkey, timestamp): df => begin
        df = CSV.read(filename)
        df[!, indexkey] = map(timestamp, eachrow(df))
        df
    end ~ preserve::DataFrame

    store(df, indexkey, index): s => begin
        df[df[!, indexkey] .== index, :][1, :]
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
