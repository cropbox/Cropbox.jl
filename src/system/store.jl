using DataFrames: DataFrames, DataFrame
import Dates
using TimeZones: TimeZones, ZonedDateTime, @tz_str
using TypedTables: TypedTables, Table
import CSV

@system StoreBase begin
    filename => "" ~ preserve::String(parameter)
    ik: indexkey => :index ~ preserve::Symbol(parameter)

    i(t=context.clock.tick): index => t + 1 ~ track::Int
    ix: indexer ~ hold

    s: store ~ hold
end

@system DataFrameStore(StoreBase) begin
    ix(; r::DataFrames.DataFrameRow): indexer => DataFrames.row(r) ~ call::Int

    df(filename, ik, ix): dataframe => begin
        df = CSV.File(filename) |> DataFrames.DataFrame |> unitfy
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

@system DayStore(DataFrameStore) begin
    i(context.clock.time): index ~ track::Int(u"d")

    daykey => :day ~ preserve::Symbol(parameter)
    ix(daykey; r::DataFrames.DataFrameRow): indexer => r[daykey] ~ call::Int(u"d")
end

@system DateStore(DataFrameStore) begin
    calendar(context) ~ ::Calendar
    i(t=calendar.time): index => Dates.Date(t) ~ track::Dates.Date

    datekey => :date ~ preserve::Symbol(parameter)
    ix(datekey; r::DataFrames.DataFrameRow): indexer => r[datekey] ~ call::Dates.Date
end

@system TimeStore(DataFrameStore) begin
    calendar(context) ~ ::Calendar
    i(calendar.time): index ~ track::ZonedDateTime

    datekey => :date ~ preserve::Symbol(parameter)
    timekey => :time ~ preserve::Symbol(parameter)
    tz: timezone => tz"UTC" ~ preserve::TimeZones.TimeZone(parameter)
    ix(datekey, timekey, tz; r::DataFrames.DataFrameRow): indexer => begin
        #HACK: handle ambiguous time conversion under DST
        occurrence = 1
        i = DataFrames.row(r)
        if i > 1
            r0 = parent(r)[i-1, :]
            r0[timekey] == r[timekey] && (occurrence = 2)
        end
        dt = DateTime(r[datekey], r[timekey])
        ZonedDateTime(dt, tz, occurrence)
    end ~ call::ZonedDateTime
end

@system TableStore(StoreBase) begin
    #TODO: avoid dynamic dispatch on Table/NamedTuple
    ix(; i::Int, r::NamedTuple): indexer => i ~ call::Int
    tb(filename, ik, ix): table => begin
        tb = CSV.File(filename) |> TypedTables.FlexTable
        setproperty!(tb, ik, map(enumerate(eachrow(tb))) do (i, r)
            ix(i, r)
        end)
        Table(tb)
    end ~ preserve::Table(extern, parameter)
    s(tb, i): store => tb[i] ~ track::NamedTuple
end

export DataFrameStore, DayStore, DateStore, TimeStore, TableStore
