using Test

include("root.jl")

import Colors: RGBA
root_maize = (
    :PlantContainer => (
        :r1 => 5,
        :r2 => 5,
        :height => 50,
    ),
    :RootArchiteture => :maxB => 5,
    :MyBaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (
        :lb => 0.1 ± 0.01,
        :la => 18.0 ± 1.8,
        :ln => 0.6 ± 0.06,
        :lmax => 89.7 ± 7.4,
        :r => 6.0 ± 0.6,
        :Δx => 0.5,
        :σ => 10,
        :θ => 80 ± 8,
        :N => 1.5,
        :a => 0.04 ± 0.004,
        :color => RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (
        :lb => 0.2 ± 0.04,
        :la => 0.4 ± 0.04,
        :ln => 0.4 ± 0.03,
        :lmax => 0.6 ± 1.6,
        :r => 2.0 ± 0.2,
        :Δx => 0.1,
        :σ => 20,
        :θ => 70 ± 15,
        :N => 1,
        :a => 0.03 ± 0.003,
        :color => RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (
        :lb => 0,
        :la => 0.4 ± 0.02,
        :ln => 0,
        :lmax => 0.4,
        :r => 2.0 ± 0.2,
        :Δx => 0.1,
        :σ => 20,
        :θ => 70 ± 10,
        :N => 2,
        :a => 0.02 ± 0.002,
        :color => RGBA(0, 0, 1, 1),
    )
)
root_switchgrass_N = (
    :RootArchiteture => :maxB => 5,
    :MyBaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (
        :lb => 0.41 ± 0.26,
        :la => 0.63 ± 0.50,
        :ln => 0.27 ± 0.07,
        :lmax => 33.92 ± 22.81,
        :r => 1 ± 0.1,
        :Δx => 0.5,
        :σ => 9,
        :θ => 60 ± 6,
        :N => 1.5,
        :a => (0.62 ± 0.06)u"mm",
        :color => RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (
        :lb => 0.63 ± 0.45,
        :la => 1.12 ± 1.42,
        :ln => 0.23 ± 0.11,
        :lmax => 5.61 ± 6.88,
        :r => 0.21 ± 0.02,
        :Δx => 0.1,
        :σ => 18,
        :θ => 60 ± 6,
        :N => 1,
        :a => (0.17 ± 0.02)u"mm",
        :color => RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (
        :lb => 0.45 ± 0.64,
        :la => 0.71 ± 0.64,
        :ln => 0.14 ± 0.10,
        :lmax => 2.61 ± 2.99,
        :r => 0.08 ± 0.01,
        :Δx => 0.1,
        :σ => 20,
        :θ => 60 ± 6,
        :N => 2,
        :a => (0.19 ± 0.02)u"mm",
        :color => RGBA(0, 0, 1, 1),
    )
)
root_switchgrass_W = (
    :RootArchiteture => :maxB => 15,
    :MyBaseRoot => :T => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (
        :lb => 3.40 ± 0.45,
        :la => 3.37 ± 2.89,
        :ln => 0.31 ± 0.06,
        :lmax => 42.33 ± 31.71,
        :r => 1 ± 0.1,
        :Δx => 0.5,
        :σ => 9,
        :θ => 60 ± 6,
        :N => 1.5,
        :a => (0.71 ± 0.07)u"mm",
        :color => RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (
        :lb => 0.59 ± 0.48,
        :la => 0.74 ± 0.87,
        :ln => 0.09 ± 0.09,
        :lmax => 1.66 ± 1.75,
        :r => 0.04 ± 0.01,
        :Δx => 0.1,
        :σ => 18,
        :θ => 60 ± 6,
        :N => 1,
        :a => (0.19 ± 0.02)u"mm",
        :color => RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (
        :lb => 0.07 ± 0.04,
        :la => 0,
        :ln => 0,
        :lmax => 0.07 ± 0.04,
        :r => 0.002 ± 0.001,
        :Δx => 0.01,
        :σ => 20,
        :θ => 60 ± 6,
        :N => 2,
        :a => (0.19 ± 0.02)u"mm", # 0.68
        :color => RGBA(0, 0, 1, 1),
    )
)

@testset "root" begin
    s = instance(Root.RootArchiteture, config=root_maize)
    r = simulate!(s, stop=50)
    @test r[!, :tick][end] > 50u"hr"
    # Root.render(s) |> open
    # Root.writevtk("test", s)
end
