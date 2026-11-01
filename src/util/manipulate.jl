import Bonito
using Bonito: DOM, CSS, Styles, @js_str

const MANIPULATE_STYLE = Styles(
    CSS("font-family" => "monospace", "font-size" => "13px", "line-height" => "1.5",
        "color" => "#4b5563", "accent-color" => "#47839c", "max-width" => "40em"),
    CSS(" label", "display" => "grid", "grid-template-columns" => "minmax(6em,25%) minmax(0,1fr)",
        "align-items" => "center", "gap" => "1em", "margin" => "0.6em 0"),
    CSS(" select", "font" => "inherit", "color" => "inherit", "background" => "transparent",
        "border" => "1px solid #d5dbe1", "border-radius" => "4px", "padding" => "0.25em 0.5em",
        "width" => "fit-content", "min-width" => "9em", "max-width" => "100%"),
    CSS(" input[type=range]", "width" => "100%", "min-width" => "0", "margin" => "0"),
    CSS(" label input[type=checkbox]", "justify-self" => "start", "transform" => "none",
        "width" => "1em", "height" => "1em", "margin" => "0", "padding" => "0", "box-shadow" => "none"),
    CSS(" label :focus-visible", "outline" => "2px solid #47839c", "outline-offset" => "2px"),
)

manipulatewidget(session, V, v, u) = begin
    V isa Type && V <: Enum && (V = collect(instances(V)))
    if V isa Bool
        w = Bonito.Checkbox(ismissing(v) ? V : v)
    elseif V isa AbstractArray{<:Union{Real,Quantity}} && !(eltype(V) <: Bool)
        V, v = deunitfy(V, u), deunitfy(v, u)
        isempty(V) && throw(ArgumentError("interactive parameter values must not be empty"))
        value = ismissing(v) ? V[(1 + length(V)) ÷ 2] : v
        w = Bonito.Slider(V; value)
        w.attributes[:onchange] = js"event => $(w.index).notify(event.target.valueAsNumber)"
    elseif V isa Union{AbstractArray,AbstractDict}
        options = collect(V)
        isempty(options) && throw(ArgumentError("interactive parameter values must not be empty"))
        f = V isa AbstractDict ? last : identity
        index = ismissing(v) ? 1 : findfirst(x -> isequal(f(x), v), options)
        isnothing(index) && throw(ArgumentError("initial value $v is not among the interactive parameter values"))
        option_to_string = V isa AbstractDict ? p -> string(first(p)) : string
        w = Bonito.Dropdown(options; index, option_to_string, style = nothing)
        return w, map(f, session, w.value)
    else
        throw(ArgumentError("unsupported values for interaction: $V"))
    end
    w, w.value
end

"""
    manipulate(f::Function; parameters, config=())

Create an interactive output updated by callback `f`, displayed as a Bonito app.
JupyterLab and Notebook require `jupyter-server-proxy` and a running Julia kernel.

# Arguments
- `f::Function`: callback returning a plot or another displayable value; interactively updated configuration `c` is provided.
- `parameters`: parameters adjustable with interactive widgets; value should be an iterable.
- `config=()`: a baseline configuration.
"""
manipulate(f::Function; parameters, config = ()) = begin
    #TODO: remove when our minimum Bonito version handles HTTP.AddressInUseError.
    B = Bonito.SERVER_CONFIGURATION
    if isnothing(Bonito.GLOBAL_SERVER[]) && B.listen_port[] == 9384 && isempty(B.proxy_url[])
        Bonito.configure_server!(listen_port = 0)
    end
    P = configure(parameters)
    C = configure(config)
    K = parameterkeys(P)
    U = parameterunits(P)
    Bonito.App(; title = "Cropbox") do session
        O = Bonito.Observable[]
        L = []
        for (s, Q) in P
            push!(L, DOM.div(string(s); style = "color:#6b5787;margin-top:0.5em"))
            for (k, V) in Q
                u = fieldunit(s, k)
                w, o = manipulatewidget(session, V, option(C, s, k), u)
                n = if w isa Bonito.Slider
                    readout = DOM.output(o[]; style = "min-width:3em;text-align:right;color:#47839c")
                    Bonito.onjs(session, o, js"value => $(readout).textContent = value")
                    w.attributes[:oninput] = js"event => $(readout).textContent = $(w.values).value[event.target.valueAsNumber - 1]"
                    DOM.div(w, readout; style = "display:flex;align-items:center;gap:0.75em;min-width:0")
                else
                    w
                end
                push!(O, o)
                push!(L, DOM.label(DOM.span(label(k, u)), n))
            end
        end
        output = if isempty(O)
            f(C)
        else
            map(session, O...) do V...
                X = parameterzip(K, V, U)
                f(configure(C, X, codify(X, :__manipulate__)))
            end
        end
        DOM.div(DOM.div(L...; style = MANIPULATE_STYLE), output)
    end
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
manipulate(args...; parameters, config = (), kwargs...) = manipulate(function (c)
    visualize(args...; config = c, kwargs...)
end; parameters, config)

export manipulate
