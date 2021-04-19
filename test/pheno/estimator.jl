module Pheno

using Cropbox
using TimeZones
import Dates

@system Estimator begin
    year ~ preserve::int(parameter)

    # 270(+1)th days of the first year (around end of September)
    Ds: start_date_offset => 270 ~ preserve::int(u"d")

    # 150 days after the second year (around end of May)
    De: end_date_offset => 150 ~ preserve::int(u"d")

    tz: timezone => tz"UTC" ~ preserve::TimeZone(parameter)

    t0(year, tz, Ds): start_date => begin
        ZonedDateTime(year-1, 1, 1, tz) + Dates.Day(Ds)
    end ~ preserve::datetime

    t1(year, tz, De): end_date => begin
        ZonedDateTime(year, 1, 1, tz) + Dates.Day(De)
    end ~ preserve::datetime

    calendar(context, init=t0') ~ ::Calendar
    t(calendar.time): current_date ~ track::datetime

    s: store ~ provide(init=t, parameter)

    match => false ~ flag
    stop(m=match, t, t1) => (m || t >= t1) ~ flag

    T: temperature ~ drive(from=s, by=:tavg, u"°C")
end

estimate(S::Type{<:Estimator}, years; config, index=[:year, "calendar.time"], target=[:match], stop=:stop, kwargs...) = begin
    configs = @config config + !(S => :year => years)
    simulate(S; index, target, configs, stop, snap=:match, kwargs...)
end

@system BetaFuncEstimator(BetaFunction, Estimator, Controller) <: Estimator begin
    Rg: growth_requirement ~ preserve(parameter)
    Cg(ΔT): growth_cumulated ~ accumulate
    match(Cg, Rg) => Cg >= Rg ~ flag
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
    df = DataFrame(index=T, tavg=25.0);

    Rg = 1000
    config = (
        :Estimator => (
            :tz => tz"UTC",
            :store => df,
        ),
        :BetaFuncEstimator => (
            :To => 20,
            :Tx => 35,
            :Rg => Rg,
        )
    )

    @testset "single" begin
        r = Pheno.estimate(Pheno.BetaFuncEstimator, 2017; config, target=[:ΔT, :Cg, :match, :stop])
        @test nrow(r) == 1
        r1 = r[1, :]
        @test r1.match == true
        @test r1.stop == true
        @test r1.Cg >= Rg
    end

    @testset "double" begin
        r = Pheno.estimate(Pheno.BetaFuncEstimator, [2017, 2018]; config, target=[:ΔT, :Cg, :match, :stop])
        @test nrow(r) == 2
        @test all(r.match)
        @test all(r.stop)
        @test all(r.Cg .>= Rg)
    end
end
