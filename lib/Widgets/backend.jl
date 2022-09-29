abstract type AbstractBackend; end

struct DummyBackend <: AbstractBackend; end

const backends = AbstractBackend[DummyBackend()]

get_backend() = last(backends)

set_backend!(t::AbstractBackend) = push!(backends, t)

reset_backend!() = pop!(backends)
