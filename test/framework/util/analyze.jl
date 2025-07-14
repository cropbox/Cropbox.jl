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
