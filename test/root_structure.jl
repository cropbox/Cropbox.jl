using Distributions
using Unitful

using MeshCat
import GeometryTypes: Cylinder3, Point3f0
import CoordinateTransformations: AngleAxis, LinearMap, Translation

@testset "root structure" begin
    @system RootSegment begin
        parent ~ ::Union{System,Nothing}(override)
        elongation_rate: r => rand(Normal(1, 0.2)) ~ track(u"mm/hr")
        branching_angle: a => rand(Normal(20, 10))*u"°" ~ preserve(u"°")
        branching_interval: i => 3.0 ~ track(u"mm")
        branching_chance: p => clamp(rand(Normal(0.5, 0.5)), 0, 1) ~ track
        is_branching(l, ll, i, p) => (l - ll > i && p > 0.5) ~ flag
        branched_length: bl => 0 ~ preserve(u"mm", extern)
        diameter: d => 0.1 ~ track(u"mm")
        length(r): l ~ accumulate(u"mm")
        last_branching_length(x=branch["*/-1"].bl): ll => (isempty(x) ? 0. : x[1]) ~ track(u"mm")
        branch(is_branching, l) => begin
            if is_branching
                #println("branch at l = $l")
                produce(RootSegment, parent=self, branched_length=l)
            end
        end ~ produce::RootSegment
    end

    @system Root(Controller) begin
        root(context) => RootSegment(context=context, parent=nothing) ~ ::RootSegment
    end

    render(r::RootSegment) = begin
        i = 0
        visit!(v, r) = begin
            l = r.l' |> Cropbox.deunitfy
            iszero(l) && return
            d = Cropbox.deunitfy(r.d')
            m = Cylinder3{Float32}(Point3f0(0), Point3f0(0, 0, l), d)
            # put root end at parent's tip
            T1 = Translation(0, 0, -l)
            # rotate root segment along random axis (x: random, y: left or right)
            a = Cropbox.deunitfy(r.a', u"rad")
            R = AngleAxis(a, rand(), 2(rand() > 0.5) - 1, 0) |> LinearMap
            # put root segment at parent's branching point
            z = isnothing(r.parent) ? 0 : Cropbox.deunitfy(r.parent.l' - r.bl')
            T2 = Translation(0, 0, z)
            M = T2 ∘ R ∘ T1
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
    @test s.context.clock.tick' > t
    #render(s.root) |> open
end
