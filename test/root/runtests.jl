using Cropbox
using Test

include("root.jl")

# using DataFrames
# using Statistics
# import Gadfly

root_maize = (
    :RootArchitecture => :maxB => 5,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        lb = 0.1 ± 0.01,
        la = 18.0 ± 1.8,
        ln = 0.6 ± 0.06,
        lmax = 89.7 ± 7.4,
        r = 6.0 ± 0.6,
        Δx = 0.5,
        σ = 10,
        θ = 80 ± 8,
        N = 1.5,
        a = 0.04 ± 0.004,
        color = Root.RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (;
        lb = 0.2 ± 0.04,
        la = 0.4 ± 0.04,
        ln = 0.4 ± 0.03,
        lmax = 0.6 ± 1.6,
        r = 2.0 ± 0.2,
        Δx = 0.1,
        σ = 20,
        θ = 70 ± 15,
        N = 1,
        a = 0.03 ± 0.003,
        color = Root.RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (;
        lb = 0,
        la = 0.4 ± 0.02,
        ln = 0,
        lmax = 0.4,
        r = 2.0 ± 0.2,
        Δx = 0.1,
        σ = 20,
        θ = 70 ± 10,
        N = 2,
        a = 0.02 ± 0.002,
        color = Root.RGBA(0, 0, 1, 1),
    )
)
root_switchgrass_N = (
    :RootArchitecture => :maxB => 5,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        lb = 0.41 ± 0.26,
        la = 0.63 ± 0.50,
        ln = 0.27 ± 0.07,
        lmax = 33.92 ± 22.60,
        r = 1 ± 0.1,
        Δx = 0.5,
        σ = 9,
        θ = 60 ± 6,
        N = 1.5,
        a = (0.62 ± 0.41)u"mm",
        color = Root.RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (;
        lb = 0.63 ± 0.45,
        la = 1.12 ± 1.42,
        ln = 0.23 ± 0.11,
        lmax = 7.03 ± 6.84,
        r = 0.21 ± 0.02,
        Δx = 0.1,
        σ = 18,
        θ = 60 ± 6,
        N = 1,
        a = (0.22 ± 0.07)u"mm",
        color = Root.RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (;
        lb = 0.45 ± 0.64,
        la = 0.71 ± 0.64,
        ln = 0.14 ± 0.10,
        lmax = 2.77 ± 2.68,
        r = 0.08 ± 0.01,
        Δx = 0.1,
        σ = 20,
        θ = 60 ± 6,
        N = 2,
        a = (0.19 ± 0.10)u"mm",
        color = Root.RGBA(0, 0, 1, 1),
    )
)
root_switchgrass_W = (
    :RootArchitecture => :maxB => 15,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        lb = 0.40 ± 0.45,
        la = 3.37 ± 2.89,
        ln = 0.31 ± 0.06,
        lmax = 42.33 ± 30.54,
        r = 1 ± 0.1,
        Δx = 0.5,
        σ = 9,
        θ = 60 ± 6,
        N = 1.5,
        a = (0.71 ± 0.65)u"mm",
        color = Root.RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (;
        lb = 0.59 ± 0.48,
        la = 0.74 ± 0.87,
        ln = 0.09 ± 0.09,
        lmax = 1.79 ± 1.12,
        r = 0.04 ± 0.01,
        Δx = 0.1,
        σ = 18,
        θ = 60 ± 6,
        N = 1,
        a = (0.19 ± 0.08)u"mm",
        color = Root.RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (;
        lb = 0,
        la = 0.07 ± 0.04,
        ln = 0,
        lmax = 0.07 ± 0.04,
        r = 0.002 ± 0.001,
        Δx = 0.01,
        σ = 20,
        θ = 60 ± 6,
        N = 2,
        a = (0.19 ± 0.08)u"mm", # 0.68 ± 0.77
        color = Root.RGBA(0, 0, 1, 1),
    )
)
root_switchgrass_N2 = (
    :RootArchitecture => :maxB => 5,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 0 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        lb = 0.67 ± 0.25,
        la = 0.58 ± 0.96,
        ln = 0.25 ± 0.06,
        lmax = 11.85 ± 12.63,
        r = 1 ± 0.1,
        Δx = 0.5,
        σ = 9,
        θ = 60 ± 6,
        N = 1.5,
        a = (0.78 ± 0.27)u"mm",
        color = Root.RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (;
        lb = 0.20 ± 0.15,
        la = 0.94 ± 1.12,
        ln = 0.12 ± 0.06,
        lmax = 8.04 ± 7.57,
        r = 0.68 ± 0.07,
        Δx = 0.1,
        σ = 18,
        θ = 60 ± 6,
        N = 1,
        a = (0.35 ± 0.38)u"mm",
        color = Root.RGBA(0, 1, 0, 1),
    ),
)
root_switchgrass_W2 = (
    :RootArchitecture => :maxB => 15,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 0 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        lb = 0.08 ± 0.07,
        la = 4.32 ± 1.86,
        ln = 0.21 ± 0.05,
        lmax = 22.80 ± 11.94,
        r = 1 ± 0.1,
        Δx = 0.5,
        σ = 9,
        θ = 60 ± 6,
        N = 1.5,
        a = (0.40 ± 0.15)u"mm",
        color = Root.RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (;
        lb = 0.41 ± 0.35,
        la = 1.39 ± 1.00,
        ln = 0.10 ± 0.13,
        lmax = 2.37 ± 1.41,
        r = 0.10 ± 0.01,
        Δx = 0.1,
        σ = 18,
        θ = 60 ± 6,
        N = 1,
        a = (0.21 ± 0.06)u"mm",
        color = Root.RGBA(0, 1, 0, 1),
    ),
)

root_switchgrass_P = (root_switchgrass_W,
    :Clock => (;
        step = 1u"hr",
    ),
    :RootArchitecture => :maxB => 5,
    :BaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (;
        Δx = 0.5,
    ),
    :FirstOrderLateralRoot => (;
        Δx = 0.1,
    ),
    :SecondOrderLateralRoot => (;
        Δx = 1,
    )
)
root_switchgrass_KH2PO4 = (
    root_switchgrass_P,
    :PrimaryRoot => (;
        r = 1.28 ± 0.29,
    ),
    :FirstOrderLateralRoot => (;
        lmax = 1.63 ± 0.61,
        #ln = 0.163 ± 0.061,
        r = 0.31 ± 0.11,
        θ = 84.27 ± 3.03,
    ),
    :SecondOrderLateralRoot => (;
        lmax = 2.30 ± 0.65,
        r = 0.48 ± 0.15,
        θ = 41.87 ± 6.64,
    )
)
root_switchgrass_AlPO4 = (
    root_switchgrass_P,
    :PrimaryRoot => (;
        r = 1.10 ± 0.32,
    ),
    :FirstOrderLateralRoot => (;
        lmax = 1.56 ± 0.55,
        #ln = 0.156 ± 0.055,
        r = 0.33 ± 0.11,
        θ = 83.53 ± 3.42,
    ),
    :SecondOrderLateralRoot => (;
        lmax = 2.29 ± 0.60,
        r = 0.48 ± 0.13,
        θ = 34.87 ± 5.17,
    )
)
root_switchgrass_C6H17NaO24P6 = (
    root_switchgrass_P,
    :PrimaryRoot => (;
        r = 1.31 ± 0.35,
    ),
    :FirstOrderLateralRoot => (;
        lmax = 2.80 ± 0.61,
        #ln = 0.28 ± 0.061,
        r = 0.57 ± 0.09,
        θ = 78.07 ± 5.30,
    ),
    :SecondOrderLateralRoot => (;
        lmax = 3.05 ± 0.50,
        r = 0.65 ± 0.17,
        θ = 43.73 ± 6.71,
    )
)

container_pot = :Pot => (;
    r1 = 10,
    r2 = 6,
    height = 30,
)
container_rhizobox = :Rhizobox => (;
    l = 16u"inch",
    w = 10.5u"inch",
    h = 42u"inch",
)
soilcore = :SoilCore => (;
    d = 5,
    l = 20,
    x0 = 3,
    y0 = 3,
)

@testset "root" begin
    b = instance(Root.Pot, config=container_pot)
    s = instance(Root.RootArchitecture; config=root_maize, options=(; box=b), seed=0)
    r = simulate!(s, stop=50)
    @test r.tick[end] == 50u"hr"
    # Root.render(s)
    Root.writevtk(tempname(), s)
    # Root.writepvd("test", Root.RootArchitecture, config=root_maize, stop=50)
end

# @testset "switchgrass" begin
#     C = Dict(
#         :KH2PO4 => root_switchgrass_KH2PO4,
#         :AlPO4 => root_switchgrass_AlPO4,
#         :C6H17NaO24P6 => root_switchgrass_C6H17NaO24P6,
#     )
#     b = instance(Root.Rhizobox, config=container_rhizobox)
#     P = [1, 2, 3, 4, 5]u"wk"
#     R = []
#     for i in 1:10, c in (:KH2PO4, :AlPO4, :C6H17NaO24P6)
#         n = "$c-$i"
#         r = simulate(Root.RootArchitecture; config=C[c], options=(; box=b), seed=i, stop=P[end]) do D, s
#             t = s.context.clock.tick' |> u"wk"
#             if t in P
#                 p = deunitfy(t, u"wk") |> Int
#                 Root.writevtk("$n-w$p", s)
#                 G = gather!(s, Root.BaseRoot; callback=Root.gatherbaseroot!)
#                 D[1][:time] = t
#                 D[1][:treatment] = c
#                 D[1][:repetition] = i
#                 D[1][:length] = !isempty(G) ? sum([s.length' for s in G]) : 0.0u"cm"
#                 D[1][:volume] = !isempty(G) ? sum([s.length' * s.radius'^2 for s in G]) : 0.0u"mm^3"
#                 D[1][:count] = length(G)
#             else
#                 empty!(D)
#             end
#         end
#         push!(R, r)
#     end
#     df = vcat(R...)
#     combine(groupby(df, [:treatment, :time]), :length => mean, :length => std) |> display
#     Gadfly.plot(df, x=:time, y=:length, color=:treatment,
#         Gadfly.Geom.boxplot,
#         Gadfly.Scale.x_discrete,
#         Gadfly.Guide.xlabel("Time"),
#         Gadfly.Guide.ylabel("Total Root Length Per Plant"),
#         Gadfly.Guide.colorkey(title="", pos=[0.05*Gadfly.w, -0.4*Gadfly.h]),
#         Gadfly.Theme(boxplot_spacing=7*Gadfly.mm)
#     ) |> Gadfly.SVG("switchgrass_P.svg")
# end

# using DataStructures: OrderedDict
# @testset "switchgrass rhizobox" begin
#     C = OrderedDict(
#         :W => root_switchgrass_W,
#         :N => root_switchgrass_N,
#     )
#     R = []
#     for (k, c) in C
#         n = "switchgrass_$k"
#         b = instance(Root.Rhizobox, config=container_rhizobox)
#         s = instance(Root.RootArchitecture; config=c, options=(; box=b), seed=0)
#         r = simulate!(s, stop=1000) do D, s
#             G = gather!(s, Root.BaseRoot; callback=Root.gatherbaseroot!)
#             D[1][:length] = !isempty(G) ? sum([s.length' for s in G]) : 0.0u"cm"
#             D[1][:volume] = !isempty(G) ? sum([s.length' * s.radius'^2 for s in G]) : 0.0u"mm^3"
#             D[1][:count] = length(G)
#         end
#         push!(R, r)
#         plot(r, :tick, :length, kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("$n-length.pdf")
#         plot(r, :tick, :volume, yunit=u"mm^3", kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("$n-volume.pdf")
#         plot(r, :tick, :count, kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("$n-count.pdf")
#         Root.writevtk(n, s)
#     end    
#     save(x, y, f; kw...) = begin
#         K = collect(keys(C))
#         p = plot(R[1], x, y; name=string(K[1]), title=string(y), kind=:line, backend=:Gadfly, kw...)
#         for i in 2:length(R)
#             p = plot!(p, R[i], x, y; name=string(K[i]), kind=:line, backend=:Gadfly, kw...)
#         end
#         p[] |> Cropbox.Gadfly.PDF(f)
#     end
#     save(:tick, :length, "switchgrass-length.pdf")
#     save(:tick, :volume, "switchgrass-volume.pdf"; yunit=u"mm^3")
#     save(:tick, :count, "switchgrass-count.pdf")
# end

# @testset "switchgrass layer" begin
#     C = Dict(
#         :W => root_switchgrass_W,
#         :N => root_switchgrass_N,
#     )
#     for (k, c) in C
#         n = "switchgrass_$k"
#         b = instance(Root.Rhizobox, config=container_rhizobox)
#         L = [instance(Root.SoilLayer, config=:SoilLayer => (; d, t=1)) for d in 0:1:10]
#         s = instance(Root.RootArchitecture; config=c, options=(; box=b), seed=0)
#         r = simulate!(s, stop=300) do D, s
#             G = gather!(s, Root.BaseRoot; callback=Root.gatherbaseroot!)
#             for (i, l) in enumerate(L)
#                 V = [s.length' for s in G if s.ii(l)]
#                 D[1][Symbol("L$(i-1)")] = !isempty(V) ? sum(V) : 0.0u"cm"
#             end
#         end
#         plot(r, :tick, [Symbol("L$(i-1)") for i in 1:length(L)], kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("L$n.pdf")
#         Root.writevtk(n, s)
#     end
# end

# @testset "maize layer" begin
#     n = "maize"
#     b = instance(Root.Pot, config=container_pot)
#     t = 5
#     L = [instance(Root.SoilLayer, config=:SoilLayer => (; d, t)) for d in 0:t:30-t]
#     s = instance(Root.RootArchitecture; config=root_maize, options=(; box=b), seed=0)
#     r = simulate!(s, stop=500) do D, s
#         G = gather!(s, Root.BaseRoot; callback=Root.gatherbaseroot!)
#         for (i, l) in enumerate(L)
#             ll = [s.length' for s in G if s.ii(l)]
#             D[1][Symbol("L$(i-1)")] = !isempty(ll) ? sum(ll) : 0.0u"cm"
#             vl = [s.length' * s.radius'^2 for s in G if s.ii(l)]
#             D[1][Symbol("V$(i-1)")] = !isempty(vl) ? sum(vl) : 0.0u"cm^3"
#             D[1][Symbol("C$(i-1)")] = length(vl)
#         end
#     end
#     plot(r, :tick, [Symbol("L$(i-1)") for i in 1:length(L)], legend="soil depth", names=["$((i-1)*t) - $(i*t) cm" for i in 1:length(L)], title="total length", kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("L$n.pdf")
#     plot(r, :tick, [Symbol("V$(i-1)") for i in 1:length(L)], legend="soil depth", names=["$((i-1)*t) - $(i*t) cm" for i in 1:length(L)], title="total volume", yunit=u"mm^3", kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("V$n.pdf")
#     plot(r, :tick, [Symbol("C$(i-1)") for i in 1:length(L)], legend="soil depth", names=["$((i-1)*t) - $(i*t) cm" for i in 1:length(L)], title="count", kind=:line, backend=:Gadfly)[] |> Cropbox.Gadfly.PDF("C$n.pdf")
#     Root.writevtk(n, s)
# end
