module MCalibrateUnit
using Cropbox

@system Growth(Controller) begin
    a: rate => 0 ~ preserve(parameter, u"cm/hr")
    b(a)         ~ accumulate(u"m")
end

@system Model(Controller) begin
    g(context, config) ~ ::Growth
end

abstract type Family <: System end
abstract type Branch <: Family end

@system Child(Growth) <: Branch begin
    c => 1 ~ preserve(parameter)
end

@system Dynamic(Controller) begin
    g(config) => produce(Child; config) ~ produce::Family[]
end
end

module MCalibrateOuter
using Cropbox
import ..MCalibrateUnit

@system Growth(Controller) begin
    a: rate => 0 ~ preserve(parameter, u"m/hr")
end

@system Model(Controller) begin
    g(context, config) ~ ::MCalibrateUnit.Growth
end

@system Mixed(MCalibrateUnit.Growth)

@system OtherChild(MCalibrateUnit.Growth) <: MCalibrateUnit.Family

@system PairModel(Model) begin
    h(context, config) ~ ::Growth
end

@system Produced(Controller) begin
    g => produce(MCalibrateUnit.Growth) ~ produce::MCalibrateUnit.Growth
end

@system Unspecified(Controller) begin
    g(config) => produce(MCalibrateUnit.Growth; config) ~ produce
end

@system Fixed(Growth) begin
    a: rate => 0 ~ track(u"m/hr")
end
end
