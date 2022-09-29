module Widgets

using Observables, OrderedCollections
using Dates
using Colors: Colorant

import OrderedCollections: OrderedDict
import Observables: off, on, Observable, AbstractObservable, observe, ObservablePair, @map, @map!, @on

export Widget, widget, @layout!, node, scope, scope!

include("widget.jl")
include("utils.jl")
include("layout.jl")
include("backend.jl")
include("defaults.jl")
include("manipulate.jl")
include("modifiers.jl")

end # module
