@system Context begin
    self => self ~ ::System
    context => self ~ ::System

    config => configure() ~ ::Config(override)
    prequeue => Function[] ~ ::Vector{Function}
    postqueue => Function[] ~ ::Vector{Function}
    index => 0 ~ ::Int
    recite_index => 0 ~ ::Int

    clock => Clock(; context=self) ~ ::Clock
    systems ~ ::[System]
end

option(c::Context, keys...) = option(c.config, keys...)

queue!(c::Context, f::Function, p::Int) = begin
    q = (p >= 0) ? c.postqueue : c.prequeue
    push!(q, f)
end
queue!(c::Context, f, p::Int) = nothing
dequeue!(c::Context) = (empty!(c.prequeue); empty!(c.postqueue))
flush!(q::Vector{Function}) = begin
    foreach(f -> f(), q)
    empty!(q)
end
preflush!(c::Context) = flush!(c.prequeue)
postflush!(c::Context) = flush!(c.postqueue)

import DataStructures: DefaultDict, PriorityQueue, enqueue!
update!(c::Context) = begin
    #@show "update context begin"

    # process pending operations from last timestep (i.e. produce)
    #@show c.prequeue
    preflush!(c)

    # update state variables recursively
    S = collect(c)
    # d = DefaultDict{Int,Vector{Tuple{System,Symbol}}}(Vector{Tuple{System,Symbol}})
    # for s in S
    #     u = updatableordered(s)
    #     for (i, t) in u
    #         for n in t
    #             push!(d[i], (s, n))
    #         end
    #     end
    # end
    # #@show d
    # l = vcat([d[k] for k in sort(collect(keys(d)))]...)
    # for i in 1:length(l)
    #     c.index = i
    #     (s, n) = l[i]
    #     #@show (i, (s, n))
    #     value!(s, n)
    # end
    q = PriorityQueue{Tuple{System,Symbol},Int}(Base.Reverse)
    for s in S
        u = updatableordered(s)
        for (i, t) in u
            for n in t
                enqueue!(q, (s, n), i)
            end
        end
    end
    #@show q
    l = q |> collect |> Iterators.reverse |> collect
    #@show l
    for i in 1:length(l)
        c.index = i
        ((s, n), p) = l[i]
        #@show (i, ((s, n), p))
        value!(s, n)
    end
    while c.recite_index > 0
        r = c.recite_index-1
        c.recite_index = 0
        for i in 1:r
            c.index = i
            ((s, n), p) = l[i]
            #@show (i, ((s, n), p))
            value!(s, n)
        end
    end

    # process pending operations from current timestep (i.e. flag, accumulate)
    #@show c.postqueue
    postflush!(c)

    #@show "update context end"

    #TODO: process aggregate (i.e. transport) operations?
    nothing
end

advance!(c::Context) = (advance!(c.clock); update!(c))
advance!(s::System) = advance!(s.context)
recite!(c::Context) = begin
    dequeue!(c)
    recite!(c.clock)
    #@show "recite! $(c.clock.tock) index = $(c.recite_index) => $(c.index)"
    c.recite_index = c.index
end

instance(Ss::Type{<:System}...; config=configure()) = begin
    c = Context(; config=config)
    advance!(c)
    for S in Ss
        s = S(; context=c)
        push!(c.systems, s)
    end
    advance!(c)
    c.systems[1]
end

export update!, advance!, recite!, instance
