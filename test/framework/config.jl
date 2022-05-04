using DataStructures: OrderedDict

@testset "config" begin
    @testset "configure" begin
        @testset "default" begin
            c = Cropbox.Config()
            @test Cropbox.configure() == c
            @test Cropbox.configure(()) == c
            @test Cropbox.configure(nothing) == c
        end
        
        @testset "error" begin
            @test_throws ErrorException Cropbox.configure(missing)
            @test_throws ErrorException Cropbox.configure(0)
            @test_throws ErrorException Cropbox.configure(:a)
            @test_throws ErrorException Cropbox.configure("a")
        end
    end
    
    @testset "system" begin
        @testset "pair" begin
            c = :S => :a => 1
            C = Cropbox.configure(c)
            @test C[:S][:a] == 1
        end
        
        @testset "tuple" begin
            c = (:S1 => :a => 1, :S2 => :a => 2)
            C = Cropbox.configure(c)
            @test C[:S1][:a] == 1
            @test C[:S2][:a] == 2
        end
        
        @testset "vector" begin
            c = [:S1 => :a => 1, :S2 => :a => 2]
            C = Cropbox.configure(c)
            C1 = Cropbox.configure(c[1])
            C2 = Cropbox.configure(c[2])
            @test C == [C1, C2]
        end
        
        @testset "type" begin
            @system SConfigSystemType begin
                a ~ preserve(parameter)
            end
            c = SConfigSystemType => :a => 1
            C = Cropbox.configure(c)
            @test C[:SConfigSystemType][:a] == 1
        end

        @testset "type with unit" begin
            @system SConfigSystemTypeUnit begin
                a ~ preserve(parameter, u"m")
            end
            c = SConfigSystemTypeUnit => :a => 1
            C = Cropbox.configure(c)
            @test C[:SConfigSystemTypeUnit][:a] == 1u"m"
        end
    end
    
    @testset "variable" begin
        @testset "dict" begin
            v = Dict(:a => 1, :b => 2)
            C = Cropbox.configure(:S => v)
            @test C[:S][:a] == 1
            @test C[:S][:b] == 2
        end
        
        @testset "ordered dict" begin
            v = OrderedDict(:a => 1, :b => 2)
            C = Cropbox.configure(:S => v)
            @test C[:S][:a] == 1
            @test C[:S][:b] == 2
        end
        
        @testset "tuple" begin
            v = (:a => 1, :b => 2)
            C = Cropbox.configure(:S => v)
            @test C[:S][:a] == 1
            @test C[:S][:b] == 2
        end
        
        @testset "named tuple" begin
            v = (a=1, b=2)
            C = Cropbox.configure(:S => v)
            @test C[:S][:a] == 1
            @test C[:S][:b] == 2
        end
        
        @testset "pair" begin
            v = :a => 1
            C = Cropbox.configure(:S => v)
            @test C[:S][:a] == 1
        end
    end
    
    @testset "value" begin
        @testset "dict" begin
            v = Dict(:a => 1, :b => 2)
            C = Cropbox.configure(:S => :v => v)
            @test C[:S][:v] == v
        end
        
        @testset "ordered dict" begin
            v = OrderedDict(:a => 1, :b => 2)
            C = Cropbox.configure(:S => :v => v)
            @test C[:S][:v] == v
        end
        
        @testset "tuple" begin
            v = (:a => 1, :b => 2)
            C = Cropbox.configure(:S => :v => v)
            @test C[:S][:v] == v
        end
        
        @testset "named tuple" begin
            v = (a=1, b=2)
            C = Cropbox.configure(:S => :v => v)
            @test C[:S][:v] == v
        end
        
        @testset "pair" begin
            v = :a => 1
            C = Cropbox.configure(:S => :v => v)
            @test C[:S][:v] == v
        end
    end
    
    @testset "check" begin
        @system SConfigCheck begin
            a ~ preserve(parameter)
            b: bb ~ preserve(parameter)
        end
        @test Cropbox.configure(SConfigCheck => :a => 1) == @config(:SConfigCheck => :a => 1)
        @test_throws ErrorException Cropbox.configure(SConfigCheck => :aa => 2)
        @test Cropbox.configure(SConfigCheck => :b => 3) == @config(:SConfigCheck => :b => 3)
        @test Cropbox.configure(SConfigCheck => :bb => 4) == @config(:SConfigCheck => :bb => 4)
    end

    @testset "merge" begin
        @testset "tuple" begin
            c = (:S1 => (:a => 1, :b => 2), :S2 => (:a => 3, :b => 4))
            C = Cropbox.configure(c)
            @test C[:S1][:a] == 1
            @test C[:S1][:b] == 2
            @test C[:S2][:a] == 3
            @test C[:S2][:b] == 4
        end
        
        @testset "tuple override" begin
            c = (:S => (:a => 1, :b => 2), :S => :b => 3)
            C = Cropbox.configure(c)
            @test C[:S][:a] == 1
            @test C[:S][:b] == 3
        end
        
        @testset "config" begin
            C1 = Cropbox.configure(:S1 => :a => 1)
            C2 = Cropbox.configure(:S2 => :a => 2)
            C3 = Cropbox.configure(:S3 => :a => 3)
            C = Cropbox.configure(C1, C2, C3)
            @test C[:S1][:a] == 1
            @test C[:S2][:a] == 2
            @test C[:S3][:a] == 3
        end
        
        @testset "config override" begin
            C1 = Cropbox.configure(:S => :a => 1)
            C2 = Cropbox.configure(:S => :a => 2)
            C = Cropbox.configure(C1, C2)
            @test C[:S][:a] == 2
        end
    end
    
    @testset "multiply" begin
        @testset "solo" begin
            p = :S => :a => 1:2
            C = Cropbox.configmultiply(p)
            @test C == Cropbox.configure.([:S => :a => 1, :S => :a => 2])
        end
        
        @testset "duo" begin
            p1 = :S => :a => 1:2
            p2 = :S => :b => 3:4
            C = Cropbox.configmultiply(p1, p2)
            @test C == Cropbox.configure.([
                :S => (a=1, b=3), :S => (a=1, b=4),
                :S => (a=2, b=3), :S => (a=2, b=4),
            ])
        end
        
        @testset "trio" begin
            p1 = :S => :a => 1:2
            p2 = :S => :b => 3:4
            p3 = :S => :c => 5:6
            C = Cropbox.configmultiply(p1, p2, p3)
            @test C == Cropbox.configure.([
                :S => (a=1, b=3, c=5), :S => (a=1, b=3, c=6),
                :S => (a=1, b=4, c=5), :S => (a=1, b=4, c=6),
                :S => (a=2, b=3, c=5), :S => (a=2, b=3, c=6),
                :S => (a=2, b=4, c=5), :S => (a=2, b=4, c=6),
            ])
        end
        
        @testset "base" begin
            b = (:S => :c => 1)
            p1 = :S => :a => 1:2
            p2 = :S => :b => 3:4
            C = Cropbox.configmultiply(p1, p2; base=b)
            @test C == Cropbox.configure.([
                :S => (c=1, a=1, b=3), :S => (c=1, a=1, b=4),
                :S => (c=1, a=2, b=3), :S => (c=1, a=2, b=4),
            ])
        end
        
        @testset "array" begin
            b = (:S => :c => 1)
            p1 = :S => :a => 1:2
            p2 = :S => :b => 3:4
            p = [p1, p2]
            C1 = Cropbox.configmultiply(p1, p2; base=b)
            C2 = Cropbox.configmultiply(p; base=b)
            @test C1 == C2
        end
        
        @testset "array single" begin
            p = [:S => :a => 1]
            C = Cropbox.configmultiply(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p[1])
        end
        
        @testset "array single empty" begin
            p = [()]
            C = Cropbox.configmultiply(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p[1])
        end
        
        @testset "empty tuple" begin
            p = ()
            C = Cropbox.configmultiply(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p)
        end
    end
    
    @testset "expand" begin
        @testset "patch" begin
            p = :S => :a => [1, 2]
            C = Cropbox.configexpand(p)
            @test C == Cropbox.configure.([:S => :a => 1, :S => :a => 2])
        end
        
        @testset "patch with base" begin
            b = :S => :b => 0
            p = :S => :a => [1, 2]
            C = Cropbox.configexpand(p; base=b)
            @test C == Cropbox.configure.([:S => (a=1, b=0), :S => (a=2, b=0)])
        end
        
        @testset "range" begin
            p = :S => :a => 1:2
            C = Cropbox.configexpand(p)
            @test C == Cropbox.configure.([:S => :a => 1, :S => :a => 2])
        end
        
        @testset "single" begin
            p = :S => :a => 1
            C = Cropbox.configexpand(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p)
        end
        
        @testset "empty" begin
            p = ()
            C = Cropbox.configexpand(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p)
        end
    end
    
    @testset "rebase" begin
        @testset "nonempty configs + nonempty base" begin
            b = (:S => :b => 0)
            C0 = [:S => :a => 1, :S => :a => 2]
            C1 = Cropbox.configrebase(C0; base=b)
            @test C1 == Cropbox.configure.([:S => (a=1, b=0), :S => (a=2, b=0)])
        end
        
        @testset "nonempty configs + empty base" begin
            C0 = [:S => :a => 1, :S => :a => 2]
            C1 = Cropbox.configrebase(C0)
            @test C1 == Cropbox.configure.(C0)
        end
        
        @testset "empty configs + nonempty base" begin
            b = :S => :a => 1
            C0 = []
            C1 = Cropbox.configrebase(C0; base=b)
            @test C1 == [Cropbox.configure(b)]
        end
        
        @testset "empty configs + empty base" begin
            C0 = []
            C1 = Cropbox.configrebase(C0)
            @test C1 == [Cropbox.configure()]
        end
        
        @testset "single config + single base" begin
            c = :S => :a => 1
            b = :S => :b => 2
            C1 = Cropbox.configrebase(c; base=b)
            C2 = Cropbox.configure(b, c)
            @test C1 isa Array && length(C1) == 1
            @test C1[1] == C2
        end
    end

    @testset "reduce" begin
        @testset "array + single" begin
            a = [:S => :a => 1, :S => :a => 2]
            b = :S => :a => 0
            C1 = Cropbox.configreduce(a, b)
            C2 = Cropbox.configure.([b, b])
            @test C1 == C2
        end

        @testset "single + array" begin
            a = :S => :a => 0
            b = [:S => :a => 1, :S => :a => 2]
            C1 = Cropbox.configreduce(a, b)
            C2 = Cropbox.configure(b)
            @test C1 == C2
        end

        @testset "array + array" begin
            a = [:S => :a => 1, :S => :a => 2]
            b = [:S => :a => 3, :S => :a => 4]
            C1 = Cropbox.configreduce(a, b)
            C2 = Cropbox.configure(b)
            @test C1 == C2
        end

        @testset "single + single" begin
            a = :S => :a => 1
            b = :S => :a => 2
            C1 = Cropbox.configreduce(a, b)
            C2 = Cropbox.configure(b)
            @test C1 == C2
        end
    end

    @testset "macro" begin
        @testset "merge" begin
            a = :S => :a => 1
            b = :S => :b => 2
            C1 = @config a + b
            C2 = Cropbox.configure(a, b)
            @test C1 == C2
        end
        
        @testset "merge multiple" begin
            a = :S => :a => 1
            b = :S => :b => 2
            c = :S => :c => 3
            C1 = @config a + b + c
            C2 = Cropbox.configure(a, b, c)
            @test C1 == C2
        end
        
        @testset "rebase" begin
            a = :S => :a => 1
            b = [:S => :b => 1, :S => :b => 2]
            C1 = @config a + b
            C2 = Cropbox.configrebase(b; base=a)
            @test C1 == C2
        end
        
        @testset "reduce" begin
            a = :S => :a => 0
            b = [:S => :a => 1, :S => :a => 2]
            c1(a, b) = @config a + b
            c2(a, b) = Cropbox.configreduce(a, b)
            @test c1(a, b) == c2(a, b)
            @test c1(b, a) == c2(b, a)
            @test c1(b, b) == c2(b, b)
            @test c1(a, a) == c2(a, a)
        end

        @testset "multiply" begin
            a = :S => :a => [1, 2]
            b = :S => :b => [3, 4]
            C1 = @config a * b
            C2 = Cropbox.configmultiply(a, b)
            @test C1 == C2
        end
        
        @testset "multiply with base" begin
            a = :S => :a => [1, 2]
            b = :S => :b => [3, 4]
            c = :S => :c => 0
            C1 = @config c + a * b
            C2 = Cropbox.configmultiply(a, b; base=c)
            @test C1 == C2
        end
        
        @testset "expand" begin
            a = :S => :a => [1, 2]
            C1 = @config !a
            C2 = Cropbox.configexpand(a)
            @test C1 == C2
        end
        
        @testset "expand with base" begin
            a = :S => :a => [1, 2]
            b = :S => :b => 1
            C1 = @config b + !a
            C2 = Cropbox.configexpand(a; base=b)
            @test C1 == C2
        end
        
        @testset "single" begin
            a = :S => :a => 1
            C1 = @config a
            C2 = Cropbox.configure(a)
            @test C1 == C2
        end

        @testset "multi" begin
            c1 = :S => :a => 1
            c2 = :S => :b => 2
            c3 = :S => :c => 3
            c = Cropbox.configure(c1, c2, c3)
            C1 = @config(c1, c2, c3)
            C2 = @config((c1, c2, c3))
            C3 = @config (c1, c2, c3)
            C4 = @config c1, c2, c3
            @test C1 == c
            @test C2 == c
            @test C3 == c
            @test C4 == c
        end

        @testset "empty" begin
            c = Cropbox.Config()
            C1 = @config
            C2 = @config()
            C3 = @config ()
            @test C1 == c
            @test C2 == c
            @test C3 == c
        end
    end
    
    @testset "string" begin
        @testset "basic" begin
            c = "S.a" => 1
            C = Cropbox.configure(c)
            @test C[:S][:a] == 1
        end
        
        @testset "system" begin
            c = "S" => :a => 1
            C = Cropbox.configure(c)
            @test C[:S][:a] == 1
        end
        
        @testset "error" begin
            c = "S.a.b" => 1
            @test_throws ErrorException Cropbox.configure(c)
        end
    end
    
    @testset "calibrate" begin
        c = (:S1 => (:a => 1, :b => 2), :S2 => :c => 3)
        C = Cropbox.configure(c)
        K = Cropbox.parameterkeys(C)
        @test K == [(:S1, :a), (:S1, :b), (:S2, :c)]
        V = Cropbox.parametervalues(C)
        @test V == [1, 2, 3]
        P = Cropbox.parameterzip(K, V)
        @test P == C
        @test P[:S1][:a] == 1
        @test P[:S1][:b] == 2
        @test P[:S2][:c] == 3
    end
    
    @testset "parameters" begin
        @testset "basic" begin
            @system SConfigParameters begin
                a => 1 ~ preserve(parameter)
            end
            c = Cropbox.parameters(SConfigParameters)
            @test c[:SConfigParameters][:a] == 1
        end
        
        @testset "unit" begin
            @system SConfigParametersUnit begin
                a => 1 ~ preserve(u"m", parameter)
            end
            c = Cropbox.parameters(SConfigParametersUnit)
            @test c[:SConfigParametersUnit][:a] == 1u"m"
        end
        
        @testset "missing" begin
            @system SConfigParametersMissing begin
                a => 1 ~ preserve(parameter)
                b(a) => a ~ preserve(parameter)
            end
            c = Cropbox.parameters(SConfigParametersMissing)
            @test c[:SConfigParametersMissing][:a] == 1
            @test c[:SConfigParametersMissing][:b] === missing
        end
        
        @testset "alias" begin
            @system SConfigParametersAlias begin
                a: aa => 1 ~ preserve(parameter)
            end
            c = Cropbox.parameters(SConfigParametersAlias, alias=true)
            @test_throws KeyError c[:SConfigParametersAlias][:a]
            @test c[:SConfigParametersAlias][:aa] == 1
        end
        
        @testset "recursive" begin
            @system SConfigParametersRecursiveChild begin
                b => 2 ~ preserve(parameter)
            end
            @system SConfigParametersRecursive begin
                s ~ ::SConfigParametersRecursiveChild
                a => 1 ~ preserve(parameter)
            end
            c = Cropbox.parameters(SConfigParametersRecursive, recursive=true)
            @test haskey(c, :Context)
            @test haskey(c, :Clock)
            @test c[:SConfigParametersRecursive][:a] == 1
            @test c[:SConfigParametersRecursiveChild][:b] == 2
        end
        
        @testset "exclude" begin
            @system SConfigParametersExclude begin
                a => 1 ~ preserve(parameter)
            end
            X = (Cropbox.Context,)
            c = Cropbox.parameters(SConfigParametersExclude, recursive=true, exclude=X)
            @test !haskey(c, :Context)
            @test !haskey(c, :Clock)
            @test c[:SConfigParametersExclude][:a] == 1
        end
    end

    @testset "option" begin
        @testset "private" begin
            @system SConfigOptionPrivate(Controller) begin
                _a ~ preserve(parameter)
                a ~ preserve(parameter)
                b(_a) => 2a ~ track
                c(a) => 3a ~ track
            end
            c = :SConfigOptionPrivate => (_a = 1, a = 2)
            s = instance(SConfigOptionPrivate, config=c)
            @test s.b' == 2
            @test s.c' == 6
        end
    end
end
