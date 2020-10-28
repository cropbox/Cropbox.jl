import Interact

manipulate(args...; parameters, config=(), kwargs...) = begin
    P = configure(parameters)
    W = []
    L = []
    for (s, Q) in P
        push!(L, Interact.node(:div, string(s)))
        for (k, v) in Q
            #TODO: deunitfy() based on known units from parameters()
            w = Interact.widget(v; label=string(k))
            push!(W, w)
            push!(L, w)
        end
    end
    K = parameterkeys(P)
    O = [Interact.onchange(w) for w in W]
    c = map(O...) do (W...)
        V = getindex.(W)
        configure(config, parameterzip(K, V))
    end
    output = Interact.@map visualize(args...; config=&c, kwargs...)
    z = Interact.Widget{:Cropbox}(Dict(zip(K, W)); output)
    Interact.@layout!(z, Interact.vbox(L..., output))
end

export manipulate
