using DataFrames
using TimeZones
import Dates

abstract type Estimator <: System end

@system EstimatorBase(DataFrameStore) <: Estimator begin
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
    match => false ~ track::Bool
    stop(m=match, t=i, t1) => (m || t >= t1) ~ flag

    i(calendar.time): index ~ track::ZonedDateTime
    t(timezone; r::DataFrameRow): timestamp => begin
        r.timestamp
    end ~ call::ZonedDateTime

    T(s): temperature => s[:tavg] ~ track(u"°C")
end

#FIXME: compilation takes forever without @nospecialize here
@nospecialize
estimate(S::Type{<:Estimator}, years; params, index=[:year, "calendar.time"], target=[:match], stop=:stop, kwargs...) = begin
    configs = [nameof(S) => (params..., year=y) for y in years] |> collect
    r = simulate(S, [(index=index, target=target)], configs; stop=stop, kwargs...)[1]
    r[r[!, :match] .== 1, :]
end
@specialize

@system BetaFuncEstimator(BetaFunction, EstimatorBase, Controller) <: Estimator begin
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
estimate(BetaFuncEstimator, 2017; params=params, target=[:ΔT, :Cg, :match, :stop])
estimate(BetaFuncEstimator, [2017, 2018]; params=params, target=[:ΔT, :Cg, :match, :stop])
