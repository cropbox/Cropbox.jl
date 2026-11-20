module MEquationInputs
using Cropbox

factor = 7
@enum Shape Flat Round
module Source
using Cropbox
const factor = 3
@system Parent(Controller) inherited => factor ~ track
end

@system Inputs(Source.Parent) begin
    factor => 2    ~ preserve(parameter)
    shape  => Flat ~ preserve::Shape(parameter)

    y(factor) => factor * exp(0)      ~ track
    localval  => (factor = 5; factor) ~ track

    f(; factor) => factor * u"m" ~ call(u"m")
end
@system Patched(Inputs) y => factor + 1
end

@testset "macro" begin
    @testset "equation inputs" begin
        m = MEquationInputs
        s = instance(m.Patched)
        @test (s.y', s.localval', s.shape') == (3, 5, m.Flat)
        @test s.f(4) == 4u"m"
        for rhs in ("factor * x", "MEquationInputs.factor * x", "factor * x * u\"m\"")
            code = "@system Bad(Controller) begin\n    x => 1 ~ preserve\n    y(x) => $rhs ~ track\nend"
            @test_throws LoadError ["undeclared non-const global", "MEquationInputs.factor", "Bad.y", "inputs.jl:3", "y(x)"] Base.include_string(m, code, "inputs.jl")
        end
        code = "@system BadPatch{factor = 3}(Controller) y => factor ~ preserve"
        @test_throws LoadError ["MEquationInputs.factor", "BadPatch.y", "inputs.jl:1"] Base.include_string(m, code, "inputs.jl")
    end

    @testset "declaration errors" begin
        for (line, message) in (
            ("x => 1 ~ accumlate", "unknown state: accumlate"),
            ("x => 1 ~ accumlate(init = 0)", "unknown state: accumlate"),
            ("x => 1 ~ preserve(paramter)", "unsupported tag: paramter"),
            ("x", "syntax error"),
            ("a.b => 1 ~ preserve", "unrecognized variable declaration"),
        )
            code = """
            @system SDeclaration begin
                a => 1 ~ preserve
                $line
            end
            """
            for (input, n) in ((code, 3), ("@system SDeclaration $line", 1))
                @test_throws LoadError [message, "SDeclaration", line, "declaration.jl:$n"] Base.include_string(@__MODULE__, input, "declaration.jl")
            end
        end
    end

    @testset "cyclic dependency" begin
        code = """
        @system SCycle begin
            a(b) ~ track
            b(a) ~ track
        end
        """
        @test_throws LoadError ["cyclic dependency: SCycle.a → SCycle.b → SCycle.a", "cycle.jl:2", "a(b) ~ track"] Base.include_string(@__MODULE__, code, "cycle.jl")

        Base.include_string(@__MODULE__, "@system SCycleBase a(b) ~ track", "base.jl")
        code = "@system SCycleMixed(SCycleBase) b(a) ~ track"
        @test_throws LoadError ["SCycleBase.a → SCycleMixed.b → SCycleBase.a", "base.jl:1", "a(b) ~ track"] Base.include_string(@__MODULE__, code, "cycle.jl")
    end

    @testset "private name" begin
        @system SPrivateName(Controller) begin
            _a: _aa => 1 ~ preserve
            __b: __bb => 2 ~ preserve
        end
        s = instance(SPrivateName)
        @test_throws FieldAccessError s._a
        @test s.__SPrivateName__a' == 1
        @test s.__SPrivateName__aa === s.__SPrivateName__a
        @test s.__b' == 2
        @test s.__bb === s.__b
    end

    @testset "private name args" begin
        @system SPrivateNameArgs(Controller) begin
            _x: _xx => 1 ~ preserve
            a(_x) ~ preserve
            b(_x) => x ~ preserve
            c(y=_x) => y ~ preserve
            d(_y=_x) => _y ~ preserve
            aa(_xx) ~ preserve
            bb(_xx) => xx ~ preserve
            cc(y=_xx) => y ~ preserve
            dd(_y=_xx) => _y ~ preserve
        end
        s = instance(SPrivateNameArgs)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 1
        @test s.d' == 1
        @test s.aa' == 1
        @test s.bb' == 1
        @test s.cc' == 1
        @test s.dd' == 1
    end

    @testset "private name tags" begin
        @system SPrivateNameTags(Controller) begin
            _t: _true => true ~ flag
            _f: _false => false ~ flag
            a => 1 ~ track(when=_t)
            b => 1 ~ track(when=_t|_f)
            c => 1 ~ track(when=_t&_f)
            d => 1 ~ track(when=_false)
        end
        s = instance(SPrivateNameTags)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 0
        @test s.d' == 0
    end

    @testset "private name mixin" begin
        @system SPrivateNameMixin1 begin
            _a: aa1 => 1 ~ preserve
            b(_a) ~ track
        end
        @system SPrivateNameMixin2 begin
            _a: aa2 => 2 ~ preserve
            c(_a) ~ track
        end
        @eval @system SPrivateNameMixed1(SPrivateNameMixin1, SPrivateNameMixin2, Controller)
        s1 = instance(SPrivateNameMixed1)
        @test_throws FieldAccessError s1._a
        @test s1.__SPrivateNameMixin1__a' == 1
        @test s1.__SPrivateNameMixin2__a' == 2
        @test s1.b' == 1
        @test s1.c' == 2
        @eval @system SPrivateNameMixed11(SPrivateNameMixed1, Controller)
        s11 = instance(SPrivateNameMixed11)
        @test_throws FieldAccessError s11._a
        @test s11.__SPrivateNameMixin1__a' == 1
        @test s11.__SPrivateNameMixin2__a' == 2
        @test s11.b' == 1
        @test s11.c' == 2
        @test_throws ErrorException @eval @system SPrivateNameMixed2(SPrivateNameMixin1, Controller) begin
            _a: aa1 => 3 ~ preserve
        end
        @eval @system SPrivateNameMixed3(SPrivateNameMixin1, Controller) begin
            d(_a) ~ track
        end
        @test_throws UndefVarError instance(SPrivateNameMixed3)
        @eval @system SPrivateNameMixed4(SPrivateNameMixin1, SPrivateNameMixin2, Controller) begin
            d(a=__SPrivateNameMixin1__a) ~ track
            e(a=__SPrivateNameMixin2__a) ~ track
        end
        s4 = instance(SPrivateNameMixed4)
        @test s4.d' == 1
        @test s4.e' == 2
    end

    @testset "alias" begin
        @system SAlias(Controller) begin
            a: aa => 1 ~ track
            b(a, aa) => a + aa ~ track
        end
        s = instance(SAlias)
        @test s.a' == s.aa' == 1
        @test s.b' == 2
    end

    @testset "single arg without key" begin
        @system SSingleArgWithoutKey(Controller) begin
            a => 1 ~ track
            b(a) ~ track
            c(x=a) ~ track
        end
        s = instance(SSingleArgWithoutKey)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 1
    end

    @testset "bool arg" begin
        @system SBoolArg(Controller) begin
            t => true ~ preserve::Bool
            f => false ~ preserve::Bool
            a(t & f) ~ track::Bool
            b(t | f) ~ track::Bool
            c(t & !f) ~ track::Bool
            d(x=t&f, y=t|f) => x | y ~ track::Bool
        end
        s = instance(SBoolArg)
        @test s.a' == false
        @test s.b' == true
        @test s.c' == true
        @test s.d' == true
    end

    @testset "type alias" begin
        @system STypeAlias(Controller) begin
            a => -1 ~ preserve::int
            b => 1 ~ preserve::uint
            c => 1 ~ preserve::float
            r => 1//10 ~ preserve::rational
            d => true ~ preserve::bool
            e => :a ~ preserve::sym
            f => "A" ~ preserve::str
            g => nothing ~ preserve::∅
            h => missing ~ preserve::_
            i => Cropbox.Dates.Date(2021) ~ preserve::date
            j => Cropbox.TimeZones.ZonedDateTime(2021, Cropbox.TimeZones.tz"UTC") ~ preserve::datetime
        end
        s = instance(STypeAlias)
        @test s.a' isa Int64 && s.a' === -1
        @test s.b' isa UInt64 && s.b' == 1
        @test s.c' isa Float64 && s.c' === 1.0
        @test s.r' isa Rational{Int64} && s.r' === 1//10
        @test s.d' isa Bool && s.d' === true
        @test s.e' isa Symbol && s.e' === :a
        @test s.f' isa String && s.f' === "A"
        @test s.g' isa Nothing && s.g' === nothing
        @test s.h' isa Missing && s.h' === missing
        @test s.i' isa Cropbox.Dates.Date && s.i' === Cropbox.Dates.Date(2021)
        @test s.j' isa Cropbox.TimeZones.ZonedDateTime && s.j' === Cropbox.TimeZones.ZonedDateTime(2021, Cropbox.tz"UTC")
    end

    @testset "type union nothing" begin
        @system STypeUnionNothing(Controller) begin
            a ~ preserve::{sym|∅}(parameter)
        end
        a1 = :hello
        s1 = instance(STypeUnionNothing; config=:0 => :a => a1)
        @test s1.a' isa Union{Symbol,Nothing}
        @test s1.a' === a1
        a2 = nothing
        s2 = instance(STypeUnionNothing; config=:0 => :a => a2)
        @test s2.a' isa Union{Symbol,Nothing}
        @test s2.a' === a2
    end

    @testset "type union missing" begin
        @system STypeUnionMissing(Controller) begin
            a ~ preserve::{int|_}(parameter)
        end
        a1 = 0
        s1 = instance(STypeUnionMissing; config=:0 => :a => a1)
        @test s1.a' isa Union{Int64,Missing}
        @test s1.a' === a1
        a2 = missing
        # missing filtered out by genparameter, leaving no return value (nothing)
        @test_throws MethodError instance(STypeUnionMissing; config=:0 => :a => a2)
    end

    @testset "type vector single" begin
        @system STypeVectorSingle(Controller) begin
            a ~ preserve::int[](parameter)
        end
        a = [1, 2, 3]
        s = instance(STypeVectorSingle; config=:0 => :a => a)
        @test s.a' isa Vector{Int64}
        @test s.a' === a
    end

    @testset "type vector union" begin
        @system STypeVectorUnion(Controller) begin
            a ~ preserve::{sym|∅}[](parameter)
        end
        a = [:a, nothing, :c]
        s = instance(STypeVectorUnion; config=:0 => :a => a)
        @test s.a' isa Vector{Union{Symbol,Nothing}}
        @test s.a' === a
    end

    @testset "patch type" begin
        @system SPatchType{A => Int, Int => Float32, int => Float64}(Controller) begin
            a => 1 ~ preserve::A
            b => 1 ~ preserve::Int
            c => 1 ~ preserve::int
        end
        s = instance(SPatchType)
        @test s.a' isa Int
        @test s.b' isa Float32
        @test s.c' isa Float64
    end

    @testset "patch type cascade" begin
        @system SPatchTypeCascade0{A => Int} begin
            a => 1 ~ preserve::A
        end
        @eval @system SPatchTypeCascade(SPatchTypeCascade0, Controller) begin
            b => 1 ~ preserve::A
        end
        s = instance(SPatchTypeCascade)
        @test s.a' isa Int
        @test s.b' isa Int
    end

    @testset "patch const" begin
        @system SPatchConst{x = 1, y = u"m"}(Controller) begin
            a => 1 ~ accumulate(init=x, unit=y)
        end
        s = instance(SPatchConst)
        @test Cropbox.unittype(s.a) === u"m"
        @test s.a' == 1u"m"
        update!(s)
        @test s.a' == 2u"m"
    end

    @testset "override" begin
        @system SOverrideComponent begin
            a ~ track(override)
        end
        @system SOverride(Controller) begin
            c(context, a) ~ ::SOverrideComponent
            a => 1 ~ track
        end
        s = instance(SOverride)
        @test s.a' == s.c.a' == 1
        @test s.a === s.c.a
    end

    @testset "override union" begin
        @system SOverrideUnionComponent begin
            a ~ track(override)
        end
        @system SOverrideUnionTrack(Controller) begin
            c(context, a) ~ ::SOverrideUnionComponent
            a => 1 ~ track
        end
        @system SOverrideUnionPreserve(Controller) begin
            c(context, a) ~ ::SOverrideUnionComponent
            a => 1 ~ preserve
        end
        @system SOverrideUnionDrive(Controller) begin
            c(context, a) ~ ::SOverrideUnionComponent
            a => [1] ~ drive
        end
        s1 = instance(SOverrideUnionTrack)
        @test s1.a' == s1.c.a' == 1
        @test s1.a === s1.c.a
        s2 = instance(SOverrideUnionPreserve)
        @test s2.a' == s2.c.a' == 1
        @test s2.a === s2.c.a
        s3 = instance(SOverrideUnionDrive)
        @test s3.a' == s3.c.a' == 1
        @test s3.a === s3.c.a
    end

    @testset "dynamic type" begin
        @system SDynamicTypeBase(Controller)
        @system SDynamicTypeChild(Controller) <: SDynamicTypeBase
        @test SDynamicTypeChild <: SDynamicTypeBase
        @system SDynamicTypeBaseDynamic(Controller) begin
            x ~ <:SDynamicTypeBase(override)
        end
        @system SDynamicTypeBaseStatic(Controller) begin
            x ~ ::SDynamicTypeBase(override)
        end
        b = instance(SDynamicTypeBase)
        c = instance(SDynamicTypeChild)
        @test instance(SDynamicTypeBaseDynamic; options=(; x = b)).x === b
        @test instance(SDynamicTypeBaseDynamic; options=(; x = c)).x === c
        @test instance(SDynamicTypeBaseStatic; options=(; x = b)).x === b
        @test_throws MethodError instance(SDynamicTypeBaseStatic; options=(; x = c))
    end

    @testset "duplicate variable" begin
        @test_logs (:warn, "duplicate variable") @eval @system SDuplicateVariable begin
            x => 1 ~ preserve
            x => 2 ~ preserve
        end
    end

    @testset "body replacement" begin
        @system SBodyReplacement1(Controller) begin
            a => 1 ~ preserve
        end
        @eval @system SBodyReplacement2(SBodyReplacement1) begin
            a => 2
        end
        s1 = instance(SBodyReplacement1)
        s2 = instance(SBodyReplacement2)
        @test s1.a isa Cropbox.Preserve
        @test s1.a' == 1
        @test s2.a isa Cropbox.Preserve
        @test s2.a' == 2
    end

    @testset "replacement with different alias" begin
        @system SReplacementDifferentAlias1 begin
            x: aaa => 1 ~ preserve
        end
        @test_logs (:warn, "variable replaced with inconsistent alias") @eval @system SReplacementDifferentAlias2(SReplacementDifferentAlias1) begin
            x: bbb => 2 ~ preserve
        end
    end
    
    @testset "custom system" begin
        abstract type SAbstractCustomSystem <: System end
        @system SCustomSystem <: SAbstractCustomSystem
        @test SCustomSystem <: System
        @test SCustomSystem <: SAbstractCustomSystem
    end

    @testset "return" begin
        @system SReturnBase(Controller) begin
            x(t = context.clock.tick) => t   ~ track(u"m", min = 1)
            y(x)                      => 10x ~ track(u"m")
            f(; i)                    => i   ~ call
        end
        @eval @system SLocalReturn(SReturnBase) begin
            x => begin
                t < 2 && return 2t
                sum(0:t) do i
                    return 2i
                end
            end
            f => (return 2i)
        end
        s = instance(SLocalReturn)
        @test (s.x', s.y', s.f(4)) == (1u"m", 10u"m", 8)
        update!(s)
        @test (s.x', s.y') == (2u"m", 20u"m")
        update!(s)
        @test (s.x', s.y') == (6u"m", 60u"m")

        @system SBisectReturn(Controller) begin
            f(x, _ = context.clock.tick) => (x < 1 && return -1; x - 1) ~ track
            x(f)                                                        ~ bisect(lower = 0, upper = 2)
        end
        @test instance(SBisectReturn).x' == 1

        input = "@system SReturn x => (return 1) ~ preserve"
        @test_throws LoadError ["`return` in SReturn.x", "return.jl:1", "return 1"] Base.include_string(@__MODULE__, input, "return.jl")
    end
end
