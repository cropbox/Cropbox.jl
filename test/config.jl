import DataStructures: OrderedDict

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
            @test_throws ErrorException Cropbox.configure([])
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
            @test_throws ErrorException Cropbox.configure(c)
        end
        
        @testset "type" begin
            @system SConfigSystemType begin
                a ~ preserve(parameter)
            end
            c = SConfigSystemType => :a => 1
            C = Cropbox.configure(c)
            @test C[:SConfigSystemType][:a] == 1
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
            p = [:S => :a => 1:2]
            C = Cropbox.configmultiply(p)
            @test C == Cropbox.configure.([:S => :a => 1, :S => :a => 2])
        end
        
        @testset "duo" begin
            p = [:S => :a => 1:2, :S => :b => 3:4]
            C = Cropbox.configmultiply(p)
            @test C == Cropbox.configure.([
                :S => (a=1, b=3), :S => (a=1, b=4),
                :S => (a=2, b=3), :S => (a=2, b=4),
            ])
        end
        
        @testset "trio" begin
            p = [:S => :a => 1:2, :S => :b => 3:4, :S => :c => 5:6]
            C = Cropbox.configmultiply(p)
            @test C == Cropbox.configure.([
                :S => (a=1, b=3, c=5), :S => (a=1, b=3, c=6),
                :S => (a=1, b=4, c=5), :S => (a=1, b=4, c=6),
                :S => (a=2, b=3, c=5), :S => (a=2, b=3, c=6),
                :S => (a=2, b=4, c=5), :S => (a=2, b=4, c=6),
            ])
        end
        
        @testset "base" begin
            b = (:S => :c => 1)
            p = [:S => :a => 1:2, :S => :b => 3:4]
            C = Cropbox.configmultiply(p, b)
            @test C == Cropbox.configure.([
                :S => (c=1, a=1, b=3), :S => (c=1, a=1, b=4),
                :S => (c=1, a=2, b=3), :S => (c=1, a=2, b=4),
            ])
        end
        
        @testset "single" begin
            p = [:S => :a => 1]
            C = Cropbox.configmultiply(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p[1])
        end
        
        @testset "single empty" begin
            p = [()]
            C = Cropbox.configmultiply(p)
            @test C isa Array && length(C) == 1
            @test C[1] == Cropbox.configure(p[1])
        end
        
        @testset "empty tuple" begin
            p = ()
            @test_throws MethodError Cropbox.configmultiply(p)
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
            C = Cropbox.configexpand(p, b)
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
            C1 = Cropbox.configrebase(C0, b)
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
            C1 = Cropbox.configrebase(C0, b)
            @test C1 == [Cropbox.configure(b)]
        end
        
        @testset "empty configs + empty base" begin
            C0 = []
            C1 = Cropbox.configrebase(C0)
            @test C1 == [Cropbox.configure()]
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
end
