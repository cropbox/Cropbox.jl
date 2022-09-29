function manipulatelayout(backend::AbstractBackend)
    defaultlayout(backend)
end

function make_widget(binding)
    if binding.head != :(=)
        error("@manipulate syntax error.")
    end
    sym, expr = binding.args
    Expr(:call, :(=>), Expr(:quote, Symbol(sym)), Expr(:(=), esc(sym),
         Expr(:call, widget, esc(expr), Expr(:kw, :label, string(sym)))))
end

function map_block(block, symbols, throttle = nothing)
    block = esc(block)
    symbols = map(esc, symbols)
    lambda = Expr(:(->), Expr(:tuple, symbols...),
                  block)
    f = gensym()

    get_obs(wdg, throttle::Nothing = nothing) = wdg
    get_obs(wdg, throttle) = :(Observables.throttle($(esc(throttle)), $(wdg)))
    quote
        $f = $lambda
        map($f, $((get_obs(symbol, throttle) for symbol in symbols)...))
    end
end

function symbols(bindings)
    map(x->x.args[1], bindings)
end

"""
`@manipulate expr`

The @manipulate macro lets you play with any expression using widgets. `expr` needs to be a `for` loop. The `for` loop variable
are converted to widgets using the [`widget`](@ref) function (ranges become `slider`, lists of options become `togglebuttons`, etc...).
The `for` loop body is displayed beneath the widgets and automatically updated as soon as the widgets change value.

Use `throttle = df` to only update the output after a small time interval `dt` (useful if the update is costly as it prevents
multiple updates when moving for example a slider).

## Examples

```julia
using Colors

@manipulate for r = 0:.05:1, g = 0:.05:1, b = 0:.05:1
    HTML(string("<div style='color:#", hex(RGB(r,g,b)), "'>Color me</div>"))
end

@manipulate throttle = 0.1 for r = 0:.05:1, g = 0:.05:1, b = 0:.05:1
    HTML(string("<div style='color:#", hex(RGB(r,g,b)), "'>Color me</div>"))
end
```

[`@layout!`](@ref) can be used to adjust the layout of a manipulate block:

```julia
using Interact

ui = @manipulate throttle = 0.1 for r = 0:.05:1, g = 0:.05:1, b = 0:.05:1
    HTML(string("<div style='color:#", hex(RGB(r,g,b)), "'>Color me</div>"))
end
@layout! ui dom"div"(observe(_), vskip(2em), :r, :g, :b)
ui
```
"""
macro manipulate(args...)
    n = length(args)
    @assert 1 <= n <= 2
    expr = args[n]
    throttle = n == 2 ? args[1].args[2] : nothing

    if expr.head != :for
        error("@manipulate syntax is @manipulate for ",
              " [<variable>=<domain>,]... <expression> end")
    end
    block = expr.args[2]
    # remove trailing LineNumberNodes from loop body as to not just return `nothing`
    # ref https://github.com/JuliaLang/julia/pull/41857
    if Meta.isexpr(block, :block) && block.args[end] isa LineNumberNode
        pop!(block.args)
    end

    if expr.args[1].head == :block
        bindings = expr.args[1].args
    else
        bindings = [expr.args[1]]
    end
    syms = symbols(bindings)

    widgets = map(make_widget, bindings)

    dict = Expr(:call, :OrderedDict, widgets...)
    quote
        local children = $dict
        local output = $(map_block(block, syms, throttle))
        local layout = manipulatelayout(get_backend())
        Widget{:manipulate}(children, output=output, layout=layout)
    end
end
