using Distributions

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: IdentityTransformation, LinearMap, RotZX, Transformation, Translation
import Colors: RGBA
import UUIDs

@system Tropism begin
    tropsim_trials: N => 1.0 ~ preserve(parameter)
    tropism_objective(; α, β): to => 0 ~ call
end

@system Gravitropism(Tropism) begin
    parent_transformation: RT0 ~ hold
    tropism_objective(RT0; α, β): to => begin
        R = RotZX(β, α) |> LinearMap
        p = (RT0 ∘ R)([0, 0, -1])
        p[3]
    end ~ call
end

abstract type Root <: System end

@system BaseRoot(Tropism) <: Root begin
    root_order: ro => 1 ~ preserve::Int(extern)
    zone_index: zi => 0 ~ preserve::Int(extern)

    zone_type(zi, lmax, la, lp): zt => begin
        if (lmax - la) <= lp
            :apical
        elseif zi == 0
            :basal
        else
            :lateral
        end
    end ~ preserve::Symbol

    length_of_basal_zone: lb => 0.4 ~ preserve(u"cm", parameter)
    length_of_apical_zone: la => 0.5 ~ preserve(u"cm", parameter)
    length_between_lateral_branches: ln => 0.3 ~ preserve(u"cm", parameter)
    maximal_length: lmax => 3.9 ~ preserve(u"cm", parameter)

    zone_length(zt, lb, ln, la): zl => begin
        if zt == :basal
            lb
        elseif zt == :apical
            la
        else
            ln
        end
    end ~ preserve(u"cm")

    timestep(context.clock.step): Δt ~ preserve(u"hr")
    elongation_rate: r => 1.0 ~ preserve(u"cm/d", parameter)
    actual_elongation_rate(r, zl, l, Δt): ar => min(r, (zl - l) / Δt) ~ track(u"cm/d")
    remaining_elongation_rate(r, ar): rr => r - ar ~ track(u"cm/d")
    remaining_length(rr, Δt): rl => rr*Δt ~ track(u"cm")
    initial_length: l0 => 0 ~ preserve(u"cm", extern)
    parent_length: lp => 0 ~ preserve(u"cm", extern)
    length(ar): l ~ accumulate(init=l0, u"cm")

    axial_resolution: Δx => 1 ~ preserve(u"cm", parameter)
    standard_deviation_of_angle: σ => 30 ~ preserve(u"°", parameter)
    normalized_standard_deviation_of_angle(σ, nounit(Δx)): σ_Δx => sqrt(Δx)*σ ~ track(u"°")

    insertion_angle: θ => 30 ~ preserve(u"°", parameter)
    pick_angular_angle(zi, nounit(θ), nounit(σ_Δx);): pα => begin
        θ = zi == 0 ? θ : zero(θ)
        rand(Normal(θ, σ_Δx))
    end ~ call(u"°")
    pick_radial_angle(;): pβ => rand(Uniform(0, 360)) ~ call(u"°")
    angles(pα, pβ, to, N): A => begin
        n = rand() < N % 1 ? ceil(N) : floor(N)
        P = [(pα(), pβ()) for i in 0:n]
        O = [to(α, β) for (α, β) in P]
        (o, i) = findmin(O)
        P[i]
    end ~ preserve::Tuple
    angular_angle(A): α => A[1] ~ preserve(u"°")
    radial_angle(A): β => A[2] ~ preserve(u"°")

    parent_transformation: RT0 ~ track::Transformation(override)
    local_transformation(nounit(l), α, β): RT => begin
        # put root segment at parent's end
        T = Translation(0, 0, -l)
        # rotate root segment
        R = RotZX(β, α) |> LinearMap
        R ∘ T
    end ~ track::Transformation
    global_transformation(RT0, RT): RT1 => RT0 ∘ RT ~ track::Transformation

    radius: a => 0.05 ~ track(u"cm", parameter)

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

    is_grown(l, zl) => (l >= zl) ~ flag
    branch(branch, is_grown, name, successor, zt, ro, zi, rl, l, wrap(RT1)) => begin
        #FIXME: need to branch every Δx for adding consecutive segments?
        (isempty(branch) && is_grown && zt != :apical) ? [
            # consecutive segment
            produce(name, ro=ro, zi=zi+1, l0=rl, lp=l, RT0=RT1),
            # lateral branch
            produce(successor(), ro=ro+1, RT0=RT1),
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
    number_of_basal_roots: maxB => 1 ~ preserve::Int(parameter)
    initial_transformation: RT0 => IdentityTransformation() ~ track::Transformation
    roots(roots, maxB, wrap(RT0)) => begin
        [produce(PrimaryRoot, RT0=RT0) for i in (length(roots)+1):maxB]
    end ~ produce::PrimaryRoot
end

render_visit!(v, r) = begin
    l = Cropbox.deunitfy(r.l')
    a = Cropbox.deunitfy(r.a')
    (iszero(l) || iszero(a)) && return
    g = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), a)
    M = r.RT'
    # add root segment
    vv = v["$(UUIDs.uuid1())"]
    ro = r.ro'
    c = r.color'
    m = MeshCat.defaultmaterial(color=c)
    setobject!(vv, g, m)
    settransform!(vv, M)
    # visit recursively
    for cr in r.branch
        render_visit!(vv, cr)
    end
    v
end

render(r::Root) = render_visit!(Visualizer(), r)
render(R::Vector{<:Root}) = begin
    v = Visualizer()
    for r in R
        render_visit!(v, r)
    end
    v
end

o = (
    :RootSystem => :maxB => 5,
    :MyBaseRoot => :succession => [
        # P F S
          0 1 0 ; # P
          0 0 1 ; # F
          0 0 0 ; # S
    ],
    :PrimaryRoot => (
        :lb => 0.1,
        :la => 18.0,
        :ln => 0.6,
        :lmax => 89.7,
        :r => 6.0,
        :Δx => 0.5,
        :σ => 10,
        :θ => 80,
        :N => 1.5,
        :a => 0.04,
        :color => RGBA(1, 0, 0, 1),
    ),
    :FirstOrderLateralRoot => (
        :lb => 0.2,
        :la => 0.4,
        :ln => 0.4,
        :lmax => 0.6,
        :r => 2.0,
        :Δx => 1,
        :σ => 20,
        :θ => 70,
        :N => 1,
        :a => 0.03,
        :color => RGBA(0, 1, 0, 1),
    ),
    :SecondOrderLateralRoot => (
        :lb => 0,
        :la => 0.4,
        :ln => 0,
        :lmax => 0.4,
        :r => 2.0,
        :Δx => 0.1,
        :σ => 20,
        :θ => 70,
        :N => 2,
        :a => 0.02,
        :color => RGBA(0, 0, 1, 1),
    )
)
s = instance(RootSystem, config=o)
simulate!(s, stop=100)
# render(s.roots') |> open
