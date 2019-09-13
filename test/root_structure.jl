using Distributions
using Unitful

@testset "root structure" begin
    @system R begin
        parent => self ~ ::System(override)
        elongation_rate: r => rand(Normal(1, 0.2)) ~ track(u"cm")
        branching_angle => rand(Normal(20, 10))*u"°" ~ preserve(u"°")
        branching_interval: i => 3.0 ~ track(u"cm")
        branching_chance: p => clamp(rand(Normal(0.5, 0.5)), 0, 1) ~ track
        is_branching(l, ll, i, p) => (l - ll > i && p > 0.5) ~ flag
        branched_length(pl=parent.length, l): bl => pl ~ preserve(u"cm")
        diameter => 0.1 ~ track(u"cm")
        length(r): l ~ accumulate(u"cm")
        last_branching_length(x=branch["*/-1"].bl): ll => (isempty(x) ? 0. : x[1]) ~ track(u"cm")
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
        # s
    end

    s = instance(R)
    #d = []
    while Cropbox.value(s.context.clock.tick) <= 30.0
        advance!(s)
        #push!(d, (transform(collect(r))))
    end
    @test Cropbox.value(s.context.clock.tick) > 30.0
    #render(r)
    #write(d, tmp_path/'root.json')
end
