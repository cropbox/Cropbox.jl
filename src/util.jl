growing_degree_days(T, T_base; T_opt=nothing, T_max=nothing) = begin
    T = ustrip(unitfy(T, u"°C"))
    T_opt = !isnothing(T_opt) && ustrip(unitfy(T_opt, u"°C"))
    T_max = !isnothing(T_max) && ustrip(unitfy(T_max, u"°C"))
    !isnothing(T_opt) && (T = min(T, T_opt))
    !isnothing(T_max) && (T = T >= T_max ? T_base : T)
    max(T - T_base, 0)
end

beta_thermal_func(T, T_opt, T_max, T_min=0; beta=1) = begin
    T = ustrip(unitfy(T, u"°C"))
    T_opt = ustrip(unitfy(T_opt, u"°C"))
    T_max = ustrip(unitfy(T_max, u"°C"))
    T_min = ustrip(unitfy(T_min, u"°C"))
    !(T_min < T < T_max) && return 0
    !(T_min < T_opt < T_max) && return 0
    # beta function, See Yin et al. (1995), Ag For Meteorol., Yan and Hunt (1999) AnnBot, SK
    T_on = (T_opt - T_min)
    T_xo = (T_max - T_opt)
    f = (T - T_min) / T_on
    g = (T_max - T) / T_xo
    alpha = beta * T_on / T_xo
    f^alpha * g^beta
end

q10_thermal_func(T, T_opt; Q10=2) = begin
    T = ustrip(unitfy(T, u"°C"))
    T_opt = ustrip(unitfy(T_opt, u"°C"))
    Q10^((T - T_opt) / 10)
end

export growing_degree_days, beta_thermal_func, q10_thermal_func
