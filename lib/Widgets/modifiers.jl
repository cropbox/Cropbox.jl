function triggeredby!(o::AbstractObservable, a::AbstractObservable, b::AbstractObservable)
    update = Ref(true)
    on(o) do t
        update[] && (a[] = t)
    end
    on(b) do _
        update[] = false
        o[] = a[]
        update[] = true
    end
    o
end

triggeredby(a::AbstractObservable{T}, b::AbstractObservable) where {T} =
    triggeredby!(Observable{T}(a[]), a, b)

"""
`onchange(w::AbstractWidget, change = w[:changes])`

Return a widget that's identical to `w` but only updates on `change`. For a slider it corresponds to releasing it
and for a textbox it corresponds to losing focus.

## Examples

```julia
sld = slider(1:100) |> onchange # update on release
txt = textbox("Write here") |> onchange # update on losing focuse
```
"""
function onchange(w::AbstractWidget{T}, change = w[:changes]) where T
    o = triggeredby(w, change)
    Widget{T}(w, output = o)
end
