import DataStructures: OrderedDict

@testset "config" begin
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
