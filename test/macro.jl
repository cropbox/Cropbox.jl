@testset "macro" begin
    @testset "private name" begin
        @system SPrivateName(Controller) begin
            _a: _aa => 1 ~ preserve
            __b: __bb => 2 ~ preserve
        end
        s = instance(SPrivateName)
        @test_throws ErrorException s._a
        @test s.__SPrivateName__a' == 1
        @test s._aa === s.__SPrivateName__a
        @test s.__b' == 2
        @test s.__bb === s.__b
    end

    @testset "private name args" begin
        @system SPrivateNameArgs(Controller) begin
            _x: xx => 1 ~ preserve
            a(_x) ~ preserve
            b(_x) => x ~ preserve
            c(y=_x) => y ~ preserve
            d(_y=_x) => _y ~ preserve
            e(xx) ~ preserve
        end
        s = instance(SPrivateNameArgs)
        @test s.a' == 1
        @test s.b' == 1
        @test s.c' == 1
        @test s.d' == 1
        @test s.e' == 1
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
        @test_throws ErrorException s1._a
        @test s1.__SPrivateNameMixin1__a' == 1
        @test s1.__SPrivateNameMixin2__a' == 2
        @test s1.b' == 1
        @test s1.c' == 2
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
            d => true ~ preserve::bool
            e => :a ~ preserve::sym
            f => "A" ~ preserve::str
            g => nothing ~ preserve::∅
            h => missing ~ preserve::_
        end
        s = instance(STypeAlias)
        @test s.a' isa Int64 && s.a' === -1
        @test s.b' isa UInt64 && s.b' == 1
        @test s.c' isa Float64 && s.c' === 1.0
        @test s.d' isa Bool && s.d' === true
        @test s.e' isa Symbol && s.e' === :a
        @test s.f' isa String && s.f' === "A"
        @test s.g' isa Nothing && s.g' === nothing
        @test s.h' isa Missing && s.h' === missing
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

    @testset "type patch" begin
        @system SPatch{A => Int, Int => Float32, int => Float64}(Controller) begin
            a => 1 ~ preserve::A
            b => 1 ~ preserve::Int
            c => 1 ~ preserve::int
        end
        s = instance(SPatch)
        @test s.a' isa Int
        @test s.b' isa Float32
        @test s.c' isa Float64
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
        #TODO: reimplement more robust return checking
        @test_skip @test_throws LoadError @eval @system SReturn begin
            x => begin
                return 1
            end ~ track
        end
    end
end
