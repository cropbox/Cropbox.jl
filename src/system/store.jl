import DataFrames: DataFrame, DataFrameRow, DataFrames
import CSV

@system DataFrameStore begin
    filename => "" ~ preserve::String(parameter)

    ik: indexkey => :index ~ preserve::Symbol(optional, parameter)
    iv(; r::DataFrameRow): indexval => DataFrames.row(r) ~ call

    df(filename, ik, iv): dataframe => begin
        df = CSV.read(filename)
        if !isnothing(ik)
            df[!, ik] = map(iv, eachrow(df))
        end
        df
    end ~ preserve::DataFrame(extern, parameter)

    iv0: initial_indexval => 1 ~ preserve::Int
    i0(df, ik, iv0): initial_index => begin
        findfirst(!iszero, df[!, ik] .== iv0)
    end ~ preserve::Int
    i: index => 1 ~ accumulate::Int(init=i0)

    s(df, i): store => begin
        df[i, :]
    end ~ track::DataFrameRow{DataFrame,DataFrames.Index}
end

export DataFrameStore
