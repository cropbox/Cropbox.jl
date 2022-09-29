for op in [:filepicker, :opendialog, :savedialog, :datepicker, :colorpicker, :timepicker, :spinbox,
           :autocomplete, :input, :dropdown, :checkbox, :toggle, :togglecontent,
           :textbox, :textarea, :button, :slider, :rangeslider, :rangepicker, :entry,
           :radiobuttons, :checkboxes, :toggles, :togglebuttons, :tabs, :tabulator, :accordion,
           :wdglabel, :latex, :alert, :highlight, :notifications, :mask, :tooltip!, :confirm]
    @eval begin
        function $op(args...; kwargs...)
            length(args) > 0 && args[1] isa AbstractBackend &&
                error("Function " * string($op) * " was about to overflow: check the signature")
            $op(get_backend(), args...; kwargs...)
        end

        widget(::Val{$(Expr(:quote, op))}, args...; kwargs...) = $op(args...; kwargs...)
    end
end

function defaultlayout(::AbstractBackend)
    ui -> div(values(components(ui))..., observe(ui))
end

input(::Type{<:Bool}, args...; kwargs...) = toggle(args...; kwargs...)
input(::Type{<:AbstractString}, args...; kwargs...) = textbox(args...; kwargs...)
input(::Type{<:Dates.Date}, args...; kwargs...) = datepicker(args...; kwargs...)
input(::Type{<:Dates.Time}, args...; kwargs...) = timepicker(args...; kwargs...)
input(::Type{<:Colorant}, args...; kwargs...) = colorpicker(args...; kwargs...)
function input(::Type{T}, args...; value=Observable{Union{Nothing, T}}(nothing), kwargs...) where {T<:Real}
    spinbox(args...; value=value, kwargs...)
end

"""
`widget(args...; kwargs...)`

Automatically convert Julia types into appropriate widgets. `kwargs` are passed to the
more specific widget function.

## Examples

```julia
map(display, [
    widget(1:10),                 # Slider
    widget(false),                # Checkbox
    widget("text"),               # Textbox
    widget(1.1),                  # Spinbox
    widget([:on, :off]),          # Toggle Buttons
    widget(Dict("π" => float(π), "τ" => 2π)),
    widget(colorant"red"),        # Color picker
    widget(Dates.today()),        # Date picker
    widget(Dates.Time()),         # Time picker
    ]);
```
"""
function widget end

widget(x; kwargs...) = x
widget(x::Observable; label = nothing) = widget(get_backend(), x; label = label)
widget(x::AbstractRange; kwargs...) = slider(x; kwargs...)
widget(x::AbstractVector; kwargs...) = togglebuttons(x; kwargs...)
widget(x::AbstractVector{<:Real}; kwargs...) = slider(x; kwargs...)
widget(x::AbstractVector{Bool}; kwargs...) = togglebuttons(x; kwargs...)
widget(x::Tuple; kwargs...) = togglebuttons(collect(x); kwargs...)
widget(x::AbstractDict; kwargs...) = togglebuttons(x; kwargs...)

function widget(x::T; kwargs...) where T<:Union{Bool, AbstractString, Real, Dates.Date, Dates.Time, Colorant}
    input(T; value=x, kwargs...)
end
