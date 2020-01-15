using Distributions

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: AffineMap, LinearMap, RotMatrix, RotX, RotZ, Translation
import Colors: RGBA

abstract type Root <: System end

@system BaseRoot <: Root begin
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
    pick_angular_angle(zt, nounit(θ), nounit(σ_Δx);): pα => begin
        if zt == :basal
            rand(Normal(θ, σ_Δx))*u"°"
        else
            rand(Normal(0, σ_Δx))*u"°"
        end
    end ~ call(u"°")
    pick_radial_angle(;): pβ => rand(Uniform(0, 360)) ~ call(u"°")
    tropism_objective(zt, RT0, nounit(l); α, β): to => begin
        R = RotZ(β) * RotX(α) |> LinearMap
        p = (R ∘ RT0)([0, 0, -l])
        p[3]
    end ~ call
    tropsim_trials: N => 10 ~ preserve::Int
    angles(pα, pβ, to, N): A => begin
        P = [(pα(), pβ()) for i in 1:N]
        O = [to(α, β) for (α, β) in P]
        (o, i) = findmin(O)
        P[i]
    end ~ preserve::Tuple
    angular_angle(A): α => A[1] ~ preserve(u"°")
    radial_angle(A): β => A[2] ~ preserve(u"°")

    parent_transformation: RT0 ~ track::AffineMap(override)
    local_transformation(nounit(l), α, β): RT => begin
        # put root segment at parent's end
        T = Translation(0, 0, -l)
        # rotate root segment
        R = RotZ(β) * RotX(α) |> LinearMap
        R ∘ T
    end ~ track::AffineMap
    global_transformation(RT0, RT): RT1 => RT ∘ RT0 ~ track::AffineMap

    radius: a => 0.05 ~ track(u"cm", parameter)

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
            (ro <= 2) ? produce(successor(), ro=ro+1, zi=0, lp=l, RT0=RT1) : nothing,
        ] : nothing
    end ~ produce::Root
end

#TODO: provide @macro / function to automatically build a series of related Systems
@system MyBaseRoot(BaseRoot) <: Root begin
    succession ~ tabulate(rows=(:PrimaryRoot, :FirstOrderLateralRoot, :SecondOrderLateralRoot), parameter)
end
@system PrimaryRoot(MyBaseRoot) <: Root begin
    name => :PrimaryRoot ~ preserve::Symbol
end
@system FirstOrderLateralRoot(MyBaseRoot) <: Root begin
    name => :FirstOrderLateralRoot ~ preserve::Symbol
end
@system SecondOrderLateralRoot(MyBaseRoot) <: Root begin
    name => :SecondOrderLateralRoot ~ preserve::Symbol
end

@system RootSystem(Controller) begin
    initial_transformation: RT0 => (LinearMap(one(RotMatrix{3})) ∘ Translation(0, 0, 0)) ~ track::AffineMap
    root(context, RT0) => PrimaryRoot(context=context, RT0=RT0) ~ ::PrimaryRoot
end

render(r::Root) = begin
    i = 0
    visit!(v, r) = begin
        l = Cropbox.deunitfy(r.l')
        a = Cropbox.deunitfy(r.a')
        (iszero(l) || iszero(a)) && return
        g = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), a)
        M = r.RT'
        # add root segment
        vv = v["$i"]
        i += 1
        ro = r.ro'
        c = if ro == 1
            RGBA(1, 0, 0, 1)
        elseif ro == 2
            RGBA(0, 1, 0, 1)
        elseif ro == 3
            RGBA(0, 0, 1, 1)
        else
            RGBA(1, 1, 1, 1)
        end
        m = MeshCat.defaultmaterial(color=c)
        setobject!(vv, g, m)
        settransform!(vv, M)
        # visit recursively
        for cr in r.branch
            visit!(vv, cr)
        end
    end
    v = Visualizer()
    visit!(v, r)
    v
end

o = (
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
        :θ => 10,
        :a => 0.04,
    ),
    :FirstOrderLateralRoot => (
        :lb => 0.2,
        :la => 0.4,
        :ln => 0.4,
        :lmax => 0.6,
        :r => 2.0,
        :Δx => 1,
        :σ => 20,
        :θ => 20,
        :a => 0.03,
    ),
    :SecondOrderLateralRoot => (
        :lb => 0,
        :la => 0.4,
        :ln => 0,
        :lmax => 0.4,
        :r => 2.0,
        :Δx => 0.1,
        :σ => 20,
        :θ => 20,
        :a => 0.02,
    )
)
s = instance(RootSystem, config=o)
simulate!(s, stop=100)
# render(s.root) |> open
