using Distributions

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: IdentityTransformation, LinearMap, RotZX, Transformation, Translation
import Colors: RGBA
import UUIDs

@system Rendering

abstract type Container <: System end

@system BaseContainer(Rendering) <: Container begin
    dist(; p::Point3f0): distance => -Inf ~ call
end

@system PlantContainer(BaseContainer) <: Container begin
    r1: top_radius => 5 ~ preserve(u"cm", parameter)
    r2: bottom_radius => 5 ~ preserve(u"cm", parameter)
    h: height => 100 ~ preserve(u"cm", parameter)
    sq: square => false ~ preserve::Bool(parameter)

    dist(nounit(r1), nounit(r2), nounit(h), sq; p::Point3f0): distance => begin
        x, y, z = p
        if z < -h # below
            -z - h
        elseif 0 < z # above
            z
        else # inside: -h <= z <= 0
            w = -z / h # [0, 1]
            r = (1-w)*r1 + w*r2
            if sq
                max(abs(x), abs(y)) - r
            else
                sqrt(x^2 + y^2) - r
            end
        end
    end ~ call
end

@system Rhizobox(BaseContainer) <: Container begin
    l: length => 16u"inch" ~ preserve(u"cm", parameter)
    w: width => 10.5u"inch" ~ preserve(u"cm", parameter)
    h: height => 42u"inch" ~ preserve(u"cm", parameter)

    dist(nounit(l), nounit(w), nounit(h); p::Point3f0): distance => begin
        x, y, z = p
        if z < -h # below
            -z - h
        elseif 0 < z # above
            z
        else # inside: -h <= z <= 0
            d = abs(y) - w/2
            d < 0 ? abs(x) - l/2 : d
        end
    end ~ call
end

@system Tropism begin
    tropsim_trials: N => 1.0 ~ preserve(parameter)
    tropism_objective(; α, β): to => 0 ~ call
end

@system Plagiotropism(Tropism) begin
    parent_transformation: RT0 ~ hold
    tropism_objective(RT0; α, β): to => begin
        R = RotZX(β, α) |> LinearMap
        (RT0 ∘ R).linear[9] |> abs
    end ~ call
end

@system Gravitropism(Tropism) begin
    parent_transformation: RT0 ~ hold
    tropism_objective(RT0; α, β): to => begin
        R = RotZX(β, α) |> LinearMap
        #-(RT0 ∘ R).linear[9]
        p = (RT0 ∘ R)([0, 0, -1])
        p[3]
    end ~ call
end

@system Exotropism(Tropism) begin
    tropism_objective(; α, β): to => begin
        #HACK: not exact implementation, needs to keep initial heading
        abs(Cropbox.deunitfy(α))
    end ~ call
end

abstract type Root <: System end

@system BaseRoot(Tropism, Rendering) <: Root begin
    box ~ ::Container(override)

    root_order: ro => 1 ~ preserve::Int(extern)
    zone_index: zi => 0 ~ preserve::Int(extern)

    zone_type(lmax, la, lb, lp): zt => begin
        if (lmax - la) <= lp
            :apical
        elseif lp < lb
            :basal
        else
            :lateral
        end
    end ~ preserve::Symbol

    length_of_basal_zone: lb => 0.4 ~ preserve(u"cm", extern, parameter, min=0)
    length_of_apical_zone: la => 0.5 ~ preserve(u"cm", extern, parameter, min=0)
    length_between_lateral_branches: ln => 0.3 ~ preserve(u"cm", extern, parameter, min=0)
    maximal_length: lmax => 3.9 ~ preserve(u"cm", extern, parameter, min=0)

    zone_length(zt, lb, ln, la, lmax, lp): zl => begin
        l = if zt == :basal
            lb
        elseif zt == :apical
            la
        else
            ln
        end
    end ~ preserve(u"cm")

    timestep(context.clock.step): Δt ~ preserve(u"hr")
    elongation_rate: r => 1.0 ~ preserve(u"cm/d", parameter, min=0)
    actual_elongation_rate(r, Δx, l, Δt): ar => min(r, (Δx - l) / Δt) ~ track(u"cm/d")
    remaining_elongation_rate(r, ar): rr => r - ar ~ track(u"cm/d")
    remaining_length(rr, Δt): rl => rr*Δt ~ track(u"cm")
    initial_length: l0 => 0 ~ preserve(u"cm", extern)
    parent_length: lp => 0 ~ preserve(u"cm", extern)
    length(ar): l ~ accumulate(init=l0, u"cm")
    total_length(lp, l): lt => lp + l ~ track(u"cm")

    axial_resolution: Δx => 1 ~ preserve(u"cm", parameter)
    standard_deviation_of_angle: σ => 30 ~ preserve(u"°", parameter)
    normalized_standard_deviation_of_angle(σ, nounit(Δx)): σ_Δx => sqrt(Δx)*σ ~ track(u"°")

    insertion_angle: θ => 30 ~ preserve(u"°", parameter)
    pick_angular_angle(zi, nounit(θ), nounit(σ_Δx);): pα => begin
        θ = zi == 0 ? θ : zero(θ)
        rand(Normal(θ, σ_Δx))
    end ~ call(u"°")
    pick_radial_angle(;): pβ => rand(Uniform(0, 360)) ~ call(u"°")
    angular_angle_trials: αN => 20 ~ preserve::Int(parameter)
    raidal_angle_trials: βN => 5 ~ preserve::Int(parameter)
    angles(pα, pβ, to, N, dist=box.dist, np, αN, βN): A => begin
        n = rand() < N % 1 ? ceil(N) : floor(N)
        P = [(pα(), pβ()) for i in 0:n]
        O = [to(α, β) for (α, β) in P]
        (o, i) = findmin(O)
        (α, β) = P[i]
        d = dist(np(α, β))
        for i in 1:αN
            α1 = α + 90u"°" * (i-1)/αN
            for j in 1:βN
                d < 0 && break
                β1 = pβ()
                d1 = dist(np(α1, β1))
                if d1 < d
                    d = d1
                    α, β = α1, β1
                end
            end
            d < 0 && break
        end
        (α, β)
    end ~ preserve::Tuple
    angular_angle(A): α => A[1] ~ preserve(u"°")
    radial_angle(A): β => A[2] ~ preserve(u"°")

    parent_transformation: RT0 ~ track::Transformation(override)
    parent_position(RT0): pp => RT0([0, 0, 0]) ~ preserve::Point3f0
    new_position(pp, RT0, nounit(Δx); α, β): np => begin
        R = RotZX(β, α) |> LinearMap
        pp + (RT0 ∘ R)([0, 0, -Δx])
    end ~ call::Point3f0
    local_transformation(nounit(l), α, β): RT => begin
        # put root segment at parent's end
        T = Translation(0, 0, -l)
        # rotate root segment
        R = RotZX(β, α) |> LinearMap
        R ∘ T
    end ~ track::Transformation
    global_transformation(RT0, RT): RT1 => RT0 ∘ RT ~ track::Transformation

    radius: a => 0.05 ~ preserve(u"cm", parameter, min=0.01)

    color => RGBA(1, 1, 1, 1) ~ preserve::RGBA(parameter)

    name ~ hold
    succession ~ hold
    successor(succession, name;) => begin
        find(r) = begin
            d = succession[name]
            for (k, v) in d
                r < v ? (return k) : (r -= v)
            end
            :nothing
        end
        find(rand())
    end ~ call::Symbol

    may_segment(l, Δx, lt, lmax) => (l >= Δx && lt < lmax) ~ flag
    segment(segment, may_segment, name, box, ro, zi, rl, lb, la, ln, lmax, lt, wrap(RT1)) => begin
        (isempty(segment) && may_segment) ? [
            #HACK: keep lb/la/ln/lmax parameters same for consecutive segments
            produce(name, box=box, ro=ro, zi=zi+1, l0=rl, lb=lb, la=la, ln=ln, lmax=lmax, lp=lt, RT0=RT1),
        ] : nothing
    end ~ produce::Root

    may_branch(lt, zl, zt) => (lt >= zl && zt != :apical) ~ flag
    branch(branch, may_branch, successor, box, ro, wrap(RT1)) => begin
        (isempty(branch) && may_branch) ? [
            produce(successor(), box=box, ro=ro+1, RT0=RT1),
        ] : nothing
    end ~ produce::Root
end

#TODO: provide @macro / function to automatically build a series of related Systems
@system MyBaseRoot(BaseRoot) <: Root begin
    succession ~ tabulate(rows=(:PrimaryRoot, :FirstOrderLateralRoot, :SecondOrderLateralRoot), parameter)
end
@system PrimaryRoot(MyBaseRoot, Gravitropism) <: Root begin
    name => :PrimaryRoot ~ preserve::Symbol
end
@system FirstOrderLateralRoot(MyBaseRoot, Gravitropism) <: Root begin
    name => :FirstOrderLateralRoot ~ preserve::Symbol
end
@system SecondOrderLateralRoot(MyBaseRoot, Gravitropism) <: Root begin
    name => :SecondOrderLateralRoot ~ preserve::Symbol
end

@system RootSystem(Controller) begin
    box(context) ~ ::Rhizobox
    number_of_basal_roots: maxB => 1 ~ preserve::Int(parameter)
    initial_transformation: RT0 => IdentityTransformation() ~ track::Transformation
    roots(roots, box, maxB, wrap(RT0)) => begin
        [produce(PrimaryRoot, box=box, RT0=RT0) for i in (length(roots)+1):maxB]
    end ~ produce::PrimaryRoot
end

render(s::System) = (vis = Visualizer(); render!(s, vis); vis)
#TODO: provide macro (i.e. @mixin/@drive?) for scaffolding functions based on traits (Val)
render!(s, vis) = render!(Cropbox.mixindispatch(s, Rendering)..., vis)
render!(V::Val{:Rendering}, r::Root, vis) = begin
    l = Cropbox.deunitfy(r.l')
    a = Cropbox.deunitfy(r.a')
    (iszero(l) || iszero(a)) && return
    g = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), a)
    M = r.RT'
    # add root segment
    cvis = vis["$(UUIDs.uuid1())"]
    ro = r.ro'
    c = r.color'
    m = MeshCat.defaultmaterial(color=c)
    setobject!(cvis, g, m)
    settransform!(cvis, M)
    # visit recursively
    render!(Val(nothing), r, cvis)
end
render!(::Val, s::System, vis) = render!.(Cropbox.value.(collect(s)), Ref(vis))
render!(::Val, V::Vector{<:System}, vis) = render!.(V, Ref(vis))
render!(::Val, s, vis) = nothing

maize = (
    :PlantContainer => (
        :r1 => 5,
        :r2 => 5,
        :height => 50,
    ),
    :RootSystem => :maxB => 5,
    :MyBaseRoot => :succession => [
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
        :Δx => 1,
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
switchgrass_N = (
    :RootSystem => :maxB => 5,
    :MyBaseRoot => :succession => [
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
        :Δx => 1,
        :σ => 18,
        :θ => 60 ± 6,
        :N => 1,
        :a => (0.22 ± 0.02)u"mm",
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
s = instance(RootSystem, config=maize)
simulate!(s, stop=500)
# render(s) |> open
