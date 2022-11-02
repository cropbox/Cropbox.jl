import Interact

"""
    manipulate(f::Function; parameters, config=())

Create an interactive plot updated by callback `f`. Only works in Jupyter Notebook.

# Arguments
- `f::Function`: callback for generating a plot; interactively updated configuration `c` is provided.
- `parameters`: parameters adjustable with interactive widgets; value should be an iterable.
- `config=()`: a baseline configuration.
"""
manipulate(f::Function; parameters, config=()) = begin
    P = configure(parameters)
    C = configure(config)
    W = []
    L = []
    for (s, Q) in P
        n = Interact.node(:div, string(s))
        #HACK: use similar style/color (:light_magenta) to Config
        l = Interact.style(n, "font-family" => "monospace", "color" => :rebeccapurple)
        push!(L, l)
        for (k, V) in Q
            u = fieldunit(s, k)
            b = label(k, u)
            v = option(C, s, k)
            #HACK: support Enum types
            if V isa Type && V <: Enum
                V = collect(instances(V))
            end
            #TODO: use multiple dispatch?
            if V isa Union{AbstractArray{Symbol},AbstractArray{<:Enum},AbstractDict}
                kw = ismissing(v) ? (; label=b) : (; label=b, value=v)
                w = Interact.dropdown(V; kw...)
                d = w.layout(w).children[1].dom
                #TODO: make dropdown box smaller
                d.props[:style] = Dict("font-family" => "monospace", "padding" => "5px 10px 20px", "color" => :royalblue)
                d.children[2].props[:style] = Dict("margin" => "-13px 0 0 20px")
            elseif V isa Union{AbstractRange,AbstractArray}
                #HACK: remove units of reactive values for UI layout
                v = deunitfy(v, u)
                V = deunitfy(V, u)
                kw = ismissing(v) ? (; label=b) : (; label=b, value=v)
                w = Interact.widget(V; kw...)
                #HACK: use similar style/color (:light_blue) to Config
                d = w.layout(w).children[1].dom
                d.props[:style] = Dict("font-family" => "monospace", "width" => "80%")
                d.children[1].children[1].props[:style]["color"] = :royalblue
                d.children[1].children[1].props[:style]["white-space"] = :nowrap
            elseif V isa Bool
                kw = ismissing(v) ? (; label=b) : (; label=b, value=v)
                w = Interact.checkbox(V; kw...)
                d = w.layout(w).children[1].dom
                d.props[:style] = Dict("font-family" => "monospace", "color" => :royalblue)
                #TODO: tweak margin
                d.children[2].props[:style] = Dict("font-size" => "14px", "padding-left" => "40px")
            end
            push!(W, w)
            push!(L, w)
        end
    end
    K = parameterkeys(P)
    U = parameterunits(P)
    #HACK: update the widgets only when the change is finalized (i.e., mouse release)
    O = [Interact.onchange(w, w[!isnothing(w[:changes]) ? :changes : :index]) for w in W]
    c = map(O...) do (V...)
        X = parameterzip(K, V, U)
        _X = codify(X, :__manipulate__)
        configure(config, X, _X)
    end
    if isempty(Interact.WebIO.providers_initialised)
        @warn "interactive plot only works with a WebIO provider loaded"
        return f(c[])
    end
    output = Interact.@map f(&c)
    z = Interact.Widget{:Cropbox}(Dict(zip(K, W)); output)
    Interact.@layout!(z, Interact.vbox(L..., output))
end

"""
    manipulate(args...; parameters, kwargs...)

Create an interactive plot by calling `manipulate` with `visualize` as a callback.

See also: [`visualize`](@ref)

# Arguments
- `args`: positional arguments for `visualize`.
- `parameters`: parameters for `manipulate`.
- `kwargs`: keyword arguments for `visualize`.
"""
manipulate(args...; parameters, config=(), kwargs...) = manipulate(function (c)
    visualize(args...; config=c, kwargs...)
end; parameters, config)

export manipulate
