using Distributions
using Unitful

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: AngleAxis, LinearMap, Translation

@system RootSegment begin
    parent ~ ::Union{System,Nothing}(override)

    zone_index: zi ~ preserve::Int(extern)
    number_of_laterals: nob => 5 ~ preserve::Int(parameter)

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
    length_of_apical_zone: la => 3.0 ~ preserve(u"mm", parameter)
    length_between_lateral_branches: ln => 2.0 ~ preserve(u"mm", parameter)
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
    length(ar): [l, dx] ~ accumulate(init=l0, u"mm")

    standard_deviation_of_random_angular_change: σ => 5 ~ preserve(u"°", parameter)
    normalized_standard_deviation_of_random_angular_change(σ, nounit(dx)): σ_dx => sqrt(dx)*σ ~ track(u"°")

    insertion_angle(zt, nounit(σ_dx)): a => begin
        if zt == :basal
            rand(Normal(20, 10))*u"°"
        else
            #TODO: implement tropism functions
            rand(Normal(0, σ_dx))*u"°"
        end
    end ~ preserve(u"°")

    diameter: d => 0.1 ~ track(u"mm", parameter)

    is_grown(l, zl) => (l >= zl) ~ flag
    branch(branch, is_grown, zt, zi, rl) => begin
        if isempty(branch) && is_grown && zt != :apical
            #println("branch at l = $l")
            [
                produce(RootSegment, parent=self, zi=0), # lateral branch
                produce(RootSegment, parent=self, zi=zi+1, l0=rl), # consecutive segment
            ]
        end
    end ~ produce::RootSegment
end

@system Root(Controller) begin
    root(context) => RootSegment(context=context, parent=nothing, zi=0) ~ ::RootSegment
end


render(r::RootSegment) = begin
    i = 0
    visit!(v, r) = begin
        l = r.l' |> Cropbox.deunitfy
        iszero(l) && return
        d = Cropbox.deunitfy(r.d')
        m = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), d)
        # put root segment at parent's end
        T = Translation(0, 0, -l)
        # rotate root segment along random axis (x: random, y: left or right)
        a = Cropbox.deunitfy(r.a', u"rad")
        R = AngleAxis(a, rand(), 2(rand() > 0.5) - 1, 0) |> LinearMap
        M = R ∘ T
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
t = 30u"hr"
while s.context.clock.tick' <= t
    update!(s)
end
