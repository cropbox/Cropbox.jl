using Garlic
using GlobalSensitivity

c0 = Garlic.Examples.AoB.KM_2014_P2_SR0
P = (
        Garlic.Leaf => (;
            LER_max = (0.1, 20),
            LM_min = (0.1, 100),
            length_to_width_ratio = (0.01, 1.0),
            area_ratio = (0, 2.0),
            SG = (0.1, 5.0),
            k = (0, 5),
        ),
        Garlic.Phenology => (;
            # Emergence
            ER_max = (0.01, 1.0),
            ER_T_opt = (5, 20),
            ER_T_ceil = (20, 40),
            # FloralInitiation
            critPPD = (8, 16),
            # LeafAppearance
            LTARa_max = (0.01, 1.0),
            # _SDm = (60, 180),
            # _k = (0.01, 1.0),
            # LeafInitiation
            SD = (60, 180),
            ST = (0, 10),
            #ILN = (0, 8), #HACK: integer
            LIR_max = (0.01, 1.0),
            # Scape
            scape_appearance_threshold = (0.1, 5.0),
            flower_appearance_threshold = (0.1, 10.0),
            bulbil_appearance_threshold = (0.1, 10.0),
            # Phenology
            #leaves_generic = (0, 15), #HACK: integer
            T_opt = (10, 30),
            T_ceil = (30, 40),
        ),
        #HACK: private parameters
        :LeafAppearance => (;
            _SDm = (60, 180),
            _k = (0.01, 1.0),
        ),
        Garlic.RespirationTracker => (;
            To = (10, 30),
            Q10 = (0.1, 3.0),    
        ),
        Garlic.Carbon => (;
            Rm = (0.01, 1.0),
            Yg = (0.1, 1.0),
        ),
        Garlic.Plant => (;
            # Density
            PD0 = (40, 70),
            CDSF = (0.1, 2.0),
            CDCT = (-30, 0),
            # Mass
            initial_seed_mass = (0.01, 1.0),
            # Plant
            #primordia = (0, 10), #HACK: integer
        ),
)

mm = GlobalSensitivity.Morris(; total_num_trajectory = 1500, num_trajectory = 50)
#analyze(Garlic.Model; target = :dry_yield, parameters = P, config = c0, method = m, samples = 1000, stop = "calendar.count", snap = "?")
dfa = analyze(Garlic.Model; target = :dry_yield, parameters = P, config = c0, method = mm, samples = 1000, stop = 300u"d", snap = 300u"d")

ms = GlobalSensitivity.Sobol()
dfs = analyze(Garlic.Model; target = :dry_yield, parameters = P, config = c0, method = ms, samples = 1000, stop = 300u"d", snap = 300u"d")









using CSV, DataFrames, Gadfly

target = "dry_yield"

# 1. Load and preprocess
df = CSV.read("dfm.csv", DataFrame)
df.σ = sqrt.(df.variances)
df = filter(:σ => x -> x > 0, df)

# 2. Zoom region
xmin, xmax = -20.0, 20.0
ymin, ymax = 0.0, 50.0
# xmin, xmax = -1, 1
# ymin, ymax = 0.0, 10
# xmin, xmax = -2, 2
# ymin, ymax = 0.0, 5
# xmin, xmax = -1, 1
# ymin, ymax = 0.0, 1
#xmin, xmax = -1.0, 2.0
#ymin, ymax = 0.0, 3.0

df_box = DataFrame(
    x = [xmin, xmax, xmax, xmin, xmin],
    y = [ymin, ymin, ymax, ymax, ymin],
    group = ["box", "box", "box", "box", "box"]
)

# 3. Full plot
p1 = plot(
    layer(df,
        x=:means, y=:σ,
        color=:parameter,
        label=:parameter,
        Geom.point,
        Geom.label(position=:above)
    ),
    layer(df_box,
        x=:x, y=:y,
        group=:group,
        Geom.polygon,
        Theme(default_color="red", line_width=1.5pt)
    ),
    layer(
        xintercept=[0.0],
        Geom.vline,
        Theme(default_color="gray80", line_width=0.8pt, line_style=[:dot])
    ),
    Scale.color_discrete_hue(),
    Guide.xlabel("μ (Mean)"),
    Guide.ylabel("σ (Standard Deviation)"),
    Guide.title("Morris Sensitivity ($target)"),
    Theme(key_position=:none)
)

# 4. Zoomed data
df_zoom = filter(row -> xmin ≤ row.means ≤ xmax && ymin ≤ row.σ ≤ ymax, df)

# 5. Zoomed plot
p2 = plot(
    layer(df_zoom,
        x=:means, y=:σ,
        color=:parameter,
        label=:parameter,
        Geom.point,
        Geom.label(position=:above)
    ),
    layer(
        xintercept=[0.0],
        Geom.vline,
        Theme(default_color="gray80", line_width=0.8pt, line_style=[:dot])
    ),
    Scale.color_discrete_hue(),
    Guide.xlabel("μ (Mean)"),
    Guide.ylabel(""),
    Guide.title("Zoomed-In Region"),
    Coord.cartesian(xmin=xmin, xmax=xmax, ymin=ymin, ymax=ymax),
    Theme(key_position=:none)
)

# 6. Combine
draw(SVG("sa-garlic-morris-$target.svg", 1200px, 600px), hstack(p1, p2))








using CSV, DataFrames, Gadfly

target = "dry_yield"

# 1. Load and clean Sobol results
df = CSV.read("dfs.csv", DataFrame)
df = dropmissing(df, [:S1, :ST])
df = filter(row -> !(row.S1 == 0.0 && row.ST == 0.0), df)

# 2. 확대 영역 설정
xmin, xmax = 0.0, 0.025
ymin, ymax = 0.0, 0.12

# 3. 확대 영역 사각형 정의
df_box = DataFrame(
    x = [xmin, xmax, xmax, xmin, xmin],
    y = [ymin, ymin, ymax, ymax, ymin],
    group = ["box", "box", "box", "box", "box"]
)

# 4. 전체 플롯 (p1)
p1 = plot(
    layer(df,
        x = :S1, y = :ST,
        color = :parameter,
        label = :parameter,
        Geom.point,
        Geom.label(position = :above)
    ),
    layer(df_box,
        x = :x, y = :y,
        group = :group,
        Geom.polygon,
        Theme(default_color = "red", line_width = 1.5pt)
    ),
    Coord.cartesian(xmin = 0.0, xmax = 0.15, ymin = 0.0, ymax = 0.6),
    Scale.color_discrete_hue(),
    Guide.xlabel("First-order Index (S1)"),
    Guide.ylabel("Total-order Index (ST)"),
    Guide.title("Sobol Sensitivity Analysis ($target)"),
    Theme(key_position = :none)
)

# 5. 확대 영역 데이터 필터링
df_zoom = filter(row -> xmin ≤ row.S1 ≤ xmax && ymin ≤ row.ST ≤ ymax, df)

# 6. 확대 플롯 (p2)
p2 = plot(
    layer(df_zoom,
        x = :S1, y = :ST,
        #color = :parameter,
        label = :parameter,
        Geom.point,
        Geom.label(position = :above)
    ),
    Coord.cartesian(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
    #Scale.color_discrete_hue(),
    Guide.xlabel("First-order Index (S1)"),
    Guide.ylabel(""),
    Guide.title("Zoomed-In Region"),
    Theme(key_position = :none, default_color = "gray80")
)

# 7. 결합해서 저장
draw(SVG("sa-garlic-sobol-$target.svg", 1200px, 600px), hstack(p1, p2))
