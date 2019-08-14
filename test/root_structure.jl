using Distributions
using Unitful

@testset "root structure" begin
    @system R begin
        parent => self ~ ::System(override)
        elongation_rate: r => rand(Normal(1, 0.2)) * u"cm" ~ track(unit=u"cm")
        branching_angle => rand(Normal(20, 10)) * u"°" ~ preserve(unit=u"°")
        branching_interval: i => 3.0u"cm" ~ track(unit=u"cm")
        branching_chance => 0.5 ~ track
        is_branching(l, ll, i) => (l - ll > i) ~ flag(prob="branching_chance")
        branched_length(pl="parent.length") => pl ~ preserve(unit=u"cm")
        diameter => 0.1u"cm" ~ track(unit=u"cm")
        length(r): l => r ~ accumulate(unit=u"cm")
        last_branching_length(is_branching, l): ll => (is_branching ? l : nothing) ~ track(unit=u"cm")
        branch(self, is_branching, l) => begin
            if is_branching
                #println("branch at l = $l")
                produce(typeof(self), parent=self)
            end
        end ~ produce
    end

    render(r::R) = begin
        # s = trimesh.scene.scene.Scene()
        # #TODO: make System's own walker method?
        # def visit(r, pn=None):
        #     l = U.magnitude(r.length, 'cm')
        #     if l == 0:
        #         return
        #     m = trimesh.creation.cylinder(radius=U.magnitude(r.diameter, 'cm'), height=l, sections=4)
        #     if pn is None:
        #         m.visual.face_colors = (255, 0, 0, 255)
        #     # put segment end at origin
        #     m.apply_translation((0, 0, l/2))
        #     # put root end at parent's tip
        #     T1 = trimesh.transformations.translation_matrix((0, 0, -l))
        #     # rotate root segment along random axis (x: random, y: left or right)
        #     angle = U.magnitude(r.branching_angle, 'rad')
        #     direction = (random.random(), (random.random() > 0.5) * 2 - 1, 0)
        #     R = trimesh.transformations.rotation_matrix(angle, direction)
        #     # put root segment at parent's branching point
        #     z = 0 if pn is None else U.magnitude(r.parent.length - r.branched_length, 'cm')
        #     T2 = trimesh.transformations.translation_matrix((0, 0, z))
        #     M = trimesh.transformations.concatenate_matrices(T2, R, T1)
        #     # add root segment
        #     n = s.add_geometry(m, parent_node_name=pn, transform=M)
        #     # visit recursively
        #     [visit(cr, n) for cr in r.children]
        # visit(self)
        # s.show()
        # return s
    end

    s = instance(R)
    #d = []
    while value!(s.context.clock.time) <= 30.0
        advance!(s)
        #push!(d, (transform(collect(r))))
    end
    @test value!(s.context.clock.time) > 30.0
    #render(r)
    #write(d, tmp_path/'root.json')
end
