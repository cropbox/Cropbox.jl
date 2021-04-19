using DataFrames: DataFrames, DataFrame
import Dates
using TimeZones: TimeZones, ZonedDateTime, @tz_str
using TypedTables: TypedTables, Table
import CSV

@system StoreBase begin
    filename => "" ~ preserve::String(parameter)
    ik: indexkey => :index ~ preserve::sym(parameter)

    i(t=context.clock.tick): index => t + 1 ~ track::int
    ix: indexer ~ hold

    s: store ~ hold
end

@system DataFrameStore(StoreBase) begin
    ix(; r::Cropbox.DataFrames.DataFrameRow): indexer => Cropbox.DataFrames.row(r) ~ call::int

    df(filename, ik, ix): dataframe => begin
        df = Cropbox.CSV.File(filename) |> Cropbox.DataFrames.DataFrame |> unitfy
        df[!, ik] = map(ix, eachrow(df))
        df
    end ~ preserve::Cropbox.DataFrames.DataFrame(extern, parameter)

    gdf(df, ik): grouped_dataframe => begin
        Cropbox.DataFrames.groupby(df, ik)
    end ~ preserve::Cropbox.DataFrames.GroupedDataFrame{Cropbox.DataFrame}

    s(gdf, i): store => begin
        gdf[(i,)][1, :]
    end ~ track::Cropbox.DataFrames.DataFrameRow{Cropbox.DataFrame,Cropbox.DataFrames.Index}
end

@system DayStore(DataFrameStore) begin
    i(context.clock.time): index ~ track::int(u"d")

    daykey => :day ~ preserve::sym(parameter)
    ix(daykey; r::Cropbox.DataFrames.DataFrameRow): indexer => r[daykey] ~ call::int(u"d")
end

@system DateStore(DataFrameStore) begin
    calendar(context) ~ ::Calendar
    i(t=calendar.time): index => Cropbox.Dates.Date(t) ~ track::date

    datekey => :date ~ preserve::sym(parameter)
    ix(datekey; r::Cropbox.DataFrames.DataFrameRow): indexer => r[datekey] ~ call::date
end

@system TimeStore(DataFrameStore) begin
    calendar(context) ~ ::Calendar
    i(calendar.time): index ~ track::datetime

    datekey => :date ~ preserve::sym(parameter)
    timekey => :time ~ preserve::sym(parameter)
    tz: timezone => Cropbox.tz"UTC" ~ preserve::Cropbox.TimeZones.TimeZone(parameter)
    ix(datekey, timekey, tz; r::Cropbox.DataFrames.DataFrameRow): indexer => begin
        #HACK: handle ambiguous time conversion under DST
        occurrence = 1
        i = Cropbox.DataFrames.row(r)
        if i > 1
            r0 = parent(r)[i-1, :]
            r0[timekey] == r[timekey] && (occurrence = 2)
        end
        dt = Cropbox.Dates.DateTime(r[datekey], r[timekey])
        Cropbox.ZonedDateTime(dt, tz, occurrence)
    end ~ call::datetime
end

@system TableStore(StoreBase) begin
    #TODO: avoid dynamic dispatch on Table/NamedTuple
    ix(; i::Int, r::NamedTuple): indexer => i ~ call::int
    tb(filename, ik, ix): table => begin
        tb = Cropbox.CSV.File(filename) |> Cropbox.TypedTables.FlexTable
        setproperty!(tb, ik, map(enumerate(eachrow(tb))) do (i, r)
            ix(i, r)
        end)
        Cropbox.Table(tb)
    end ~ preserve::Cropbox.Table(extern, parameter)
    s(tb, i): store => tb[i] ~ track::NamedTuple
end

export DataFrameStore, DayStore, DateStore, TimeStore, TableStore
