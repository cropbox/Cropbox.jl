using Distributions
using Unitful

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: AffineMap, LinearMap, RotMatrix, RotX, RotZ, Translation

@system RootSegment begin
    root_order: ro => 1 ~ preserve::Int(extern)
    zone_index: zi => 0 ~ preserve::Int(extern)
    number_of_laterals: nob => 10 ~ preserve::Int(parameter)

    zone_type(zi, nob): zt => begin
        if zi == 0
            :basal
        elseif zi == nob
            :apical
        else
            :lateral
        end
    end ~ preserve::Symbol

    length_of_basal_zone: lb => 4.0 ~ preserve(u"mm", parameter)
    length_of_apical_zone: la => 5.0 ~ preserve(u"mm", parameter)
    length_between_lateral_branches: ln => 3.0 ~ preserve(u"mm", parameter)
    maximal_length(lb, la, ln, nob): lmax => (lb + la + (nob - 1)*ln) ~ preserve(u"mm")

    zone_length(zt, lb, ln, la): zl => begin
        if zt == :basal
            lb
        elseif zt == :apical
            la
        else
            ln
        end
    end ~ preserve(u"mm")

    timestep(context.clock.step): Δt ~ preserve(u"hr")
    elongation_rate: r => 1.0 ~ preserve(u"mm/hr", parameter)
    actual_elongation_rate(r, zl, l, Δt): ar => min(r, (zl - l) / Δt) ~ track(u"mm/hr")
    remaining_elongation_rate(r, ar): rr => r - ar ~ track(u"mm/hr")
    remaining_length(rr, Δt): rl => rr*Δt ~ track(u"mm")
    initial_length: l0 => 0 ~ preserve(u"mm", extern)
    parent_length: dx => 0 ~ preserve(u"mm", extern)
    length(ar): l ~ accumulate(init=l0, u"mm")

    standard_deviation_of_angle: σ => 30 ~ preserve(u"°", parameter)
    normalized_standard_deviation_of_angle(σ, nounit(dx)): σ_dx => sqrt(dx)*σ ~ track(u"°")

    insertion_angle: θ => 30 ~ preserve(u"°", parameter)
    pick_angular_angle(zt, nounit(θ), nounit(σ_dx);): pα => begin
        if zt == :basal
            rand(Normal(θ, σ_dx))*u"°"
        else
            rand(Normal(0, σ_dx))*u"°"
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

    diameter: d => 0.05 ~ track(u"mm", parameter)

    is_grown(l, zl) => (l >= zl) ~ flag
    branch(branch, is_grown, zt, ro, zi, rl, l, wrap(RT1)) => begin
        (isempty(branch) && is_grown && zt != :apical) ? [
            # consecutive segment
            produce(RootSegment, ro=ro, zi=zi+1, l0=rl, dx=l, RT0=RT1),
            # lateral branch
            (ro <= 2) ? produce(RootSegment, ro=ro+1, zi=0, dx=l, RT0=RT1) : nothing,
        ] : nothing
    end ~ produce::RootSegment
end

@system Root(Controller) begin
    initial_transformation: RT0 => (LinearMap(one(RotMatrix{3})) ∘ Translation(0, 0, 0)) ~ track::AffineMap
    root(context, RT0) => RootSegment(context=context, RT0=RT0) ~ ::RootSegment
end

render(r::RootSegment) = begin
    i = 0
    visit!(v, r) = begin
        l = Cropbox.deunitfy(r.l')
        d = Cropbox.deunitfy(r.d')
        (iszero(l) || iszero(d)) && return
        m = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), d)
        M = r.RT'
        # add root segment
        vv = v["$i"]
        i += 1
        setobject!(vv, m)
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

s = instance(Root)
simulate!(s, 100)
# render(s.root) |> open
