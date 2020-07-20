module Pheno

using Cropbox
using DataFrames
using TimeZones
import Dates

@system Estimator(DataFrameStore) begin
    year ~ preserve::Int(parameter)

    # 270(+1)th days of the first year (around end of September)
    Ds: start_date_offset => 270 ~ preserve::Int

    # 150 days after the second year (around end of May)
    De: end_date_offset => 150 ~ preserve::Int
    
    tz: timezone => tz"UTC" ~ preserve::TimeZone(parameter)

    t0(year, tz, Ds): start_date => begin
        ZonedDateTime(year-1, 1, 1, tz) + Dates.Day(Ds)
    end ~ preserve::ZonedDateTime

    t1(year, tz, De): end_date => begin
        ZonedDateTime(year, 1, 1, tz) + Dates.Day(De)
    end ~ preserve::ZonedDateTime

    calendar(context, init=t0') ~ ::Calendar

    iv(; r::DataFrameRow): indexval => begin
        ZonedDateTime(r[:timestamp], dateformat"yyyy-mm-dd HH:MM:SSzzzzz")
    end ~ call::ZonedDateTime
    iv0(t0): initial_indexval ~ preserve::ZonedDateTime

    match => false ~ track::Bool
    stop(m=match, t=calendar.time, t1) => (m || t >= t1) ~ flag

    T(s): temperature => s[:tavg] ~ track(u"°C")
end

estimate(S::Type{<:Estimator}, years; config, index=[:year, "calendar.time"], target=[:match], stop=:stop, kwargs...) = begin
    configs = @config config + !(S => :year => years)
    simulate(S; index=index, target=target, configs=configs, stop=stop, filter=:match, kwargs...)
end

@system BetaFuncEstimator(BetaFunction, Estimator, Controller) <: Estimator begin
    Rg: growth_requirement ~ preserve(parameter)
    Cg(ΔT): growth_cumulated ~ accumulate
    match(Cg, Rg) => Cg >= Rg ~ track::Bool
end

end

using DataFrames
using TimeZones
import Dates
@testset "pheno" begin
    t0 = ZonedDateTime(2016, 9, 1, tz"UTC")
    t1 = ZonedDateTime(2018, 9, 30, tz"UTC")
    dt = Dates.Hour(1)
    T = collect(t0:dt:t1);
    df = DataFrame(timestamp=T, tavg=25.0);

    Rg = 1000
    config = (
        :Estimator => (
            :tz => tz"America/New_York",
            :df => df,
        ),
        :BetaFuncEstimator => (
            :To => 20,
            :Tx => 35,
            :Rg => Rg,
        )
    )

    @testset "single" begin
        r = Pheno.estimate(Pheno.BetaFuncEstimator, 2017; config=config, target=[:ΔT, :Cg, :match, :stop])
        @test nrow(r) == 1
        r1 = r[1, :]
        @test r1.match == true
        @test r1.stop == true
        @test r1.Cg >= Rg
    end

    @testset "double" begin
        r = Pheno.estimate(Pheno.BetaFuncEstimator, [2017, 2018]; config=config, target=[:ΔT, :Cg, :match, :stop])
        @test nrow(r) == 2
        @test all(r.match)
        @test all(r.stop)
        @test all(r.Cg .>= Rg)
    end
end
