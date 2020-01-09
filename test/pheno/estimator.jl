using DataFrames
using TimeZones
import Dates

@system Estimator(DataFrameStore) begin
    year ~ preserve::Int(parameter)

    Ds: start_date_offset => 0 ~ preserve::Int(optional)

    # 150 days after new year (around end of May)
    De: end_date_offset => 150 ~ preserve::Int
    
    tz: timezone => tz"UTC" ~ preserve::TimeZone(parameter)

    t0(year, tz, Ds): start_date => begin
        if isnothing(Ds)
            ZonedDateTime(year-1, 10, 1, tz)
        else
            ZonedDateTime(year, 1, 1, tz) + Dates.Day(Ds)
        end
    end ~ preserve::ZonedDateTime

    t1(year, tz, De): end_date => begin
        ZonedDateTime(year, 1, 1, tz) + Dates.Day(De)
    end ~ preserve::ZonedDateTime

    calendar(context, init=t0') ~ ::Calendar
    t(calendar.time) ~ track::ZonedDateTime
    match => false ~ track::Bool
    stop(m=match, t, t1) => (m || t >= t1) ~ flag

    index(t) ~ track::ZonedDateTime
    timestamp(timezone; r::DataFrameRow) => begin
        r.timestamp
    end ~ call::ZonedDateTime

    #FIXME: transition to "short: long" syntax
    temperature(s): T => s[:tavg] ~ track(u"°C")
end

@system BetaFuncEstimator(BetaFunction, Estimator, Controller) begin
    Rg: growth_requirement ~ preserve(parameter)
    Cg(ΔT): growth_cumulated ~ accumulate
    match(Cg, Rg) => Cg >= Rg ~ track::Bool
end

t0 = ZonedDateTime(2017, 1, 1, tz"UTC")
t1 = ZonedDateTime(2019, 1, 1, tz"UTC")
dt = Dates.Hour(1)
T = collect(t0:dt:t1);
df = DataFrame(timestamp=T, tavg=25.0);

params = (
    :dataframe => df,
    :To => 20,
    :Tx => 35,
    :Rg => 1000,
);
config = :BetaFuncEstimator => (params..., year=2017);
simulate(BetaFuncEstimator, config=config, stop=:stop, index=[:year, "calendar.time"], target=[:ΔT, :Cg, :match, :stop]);
r = ans;
r[r[!, :match] .== 1, :]

configs = [
    :BetaFuncEstimator => (params..., year=2017),
    :BetaFuncEstimator => (params..., year=2018),
];
simulate(BetaFuncEstimator, [(index=[:year, "calendar.time"], target=[:ΔT, :Cg, :match, :stop])], configs, stop=:stop);
r = ans[1];
r[r[!, :match] .== 1, :]
