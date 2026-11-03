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

#TODO: remove this wrapper and session tracking once Bonito fixes notebook reloads
# and cross-kernel isolation; retest two notebooks in one JupyterLab page first.
# https://github.com/SimonDanisch/Bonito.jl/issues/123
# https://github.com/SimonDanisch/Bonito.jl/pull/423
struct ManipulateApp
    app::Bonito.App
end

const MANIPULATE_SESSIONS = WeakKeyDict{Bonito.Session,Nothing}()

Base.show(io::IO, ::ManipulateApp) = print(io, "Cropbox interactive output")
Base.showable(::MIME"text/html", ::ManipulateApp) = true
Base.show(io::IO, mime::MIME"text/html", widget::ManipulateApp) = begin
    # Bonito shares DOM ids and a JS connection across outputs; isolate notebook kernels.
    session = Bonito.Session(Bonito.WebSocketConnection(); asset_server = Bonito.NoServer(), title = widget.app.title)
    session.io_context[] = Bonito.get_io_context(io)
    MANIPULATE_SESSIONS[session] = nothing
    html = sprint(x -> Bonito.page_html(x, session, widget.app))
    Bonito.mark_displayed!(session)
    onload = """
        const body = this.contentDocument.body;
        const resize = () => { this.style.height = Math.ceil(body.getBoundingClientRect().height) + 'px'; };
        new this.contentWindow.ResizeObserver(resize).observe(body);
        resize();
        """
    show(io, mime, DOM.iframe(;
        srcdoc = html, title = "Cropbox interactive output", style = "border:0;width:100%;height:100px", onload))
    nothing
end

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
Notebook outputs are isolated so widgets in different notebooks do not share connections.

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
    notebook = isdefined(Main, :IJulia) && Main.IJulia.inited
    app = Bonito.App(; title = "Cropbox") do session
        O = Bonito.Observable[]
        L = []
        for (s, Q) in P
            s == Symbol(0) || push!(L, DOM.div(string(s); style = "color:#6b5787;margin-top:0.5em"))
            for (k, V) in Q
                u = fieldunit(s, k)
                w, o = manipulatewidget(session, V, option(C, s, k), u)
                n = if w isa Bonito.Slider
                    labels = [repr(v; context = :compact => true) for v in w.values[]]
                    width = max(3, maximum(length, labels))
                    readout = DOM.output(labels[w.index[]]; style = "width:$(width)ch;flex-shrink:0;text-align:right;color:#47839c")
                    Bonito.onjs(session, w.index, js"index => $(readout).textContent = $(labels)[index - 1]")
                    w.attributes[:oninput] = js"event => $(readout).textContent = $(labels)[event.target.valueAsNumber - 1]"
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
        dom = DOM.div(DOM.div(L...; style = MANIPULATE_STYLE), output)
        # Iframes do not inherit the notebook's page styles.
        notebook && pushfirst!(Bonito.children(dom), DOM.style("body {margin:0;font:14px system-ui;color:#333;} img {max-width:100%;height:auto;}"))
        dom
    end
    notebook ? ManipulateApp(app) : app
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

"""
    Cropbox.reset_manipulate()

Reset notebook widget connections if controls stop responding after a refresh.
Then re-run the `manipulate(...)` output cells; their selections return to the
initial configuration. This resets all Bonito widget sessions in the current
Julia kernel, while preserving other Julia variables and server settings.

Use only for recovery, not during normal initialization or inside `manipulate`.
"""
reset_manipulate() = begin
    foreach(close, collect(keys(MANIPULATE_SESSIONS)))
    empty!(MANIPULATE_SESSIONS)
    Bonito.Page()
end

export manipulate
