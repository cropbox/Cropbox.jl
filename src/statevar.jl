mutable struct Statevar{S<:State} <: Number
    system::System
    calc::Function #TODO: parametrise {F<:Function}
    state::S

    name::Symbol
    alias::Union{Symbol,Nothing}
    time::Statevar

    Statevar(sy, c, ST::Type{S}; stargs...) where {S<:State} = begin
        st = S(; stargs...)
        s = new{S}(sy, c, st)
        init!(s, st; stargs...)
    end
end

init!(s, st; stargs...) = begin
    initname!(s, st; stargs...)
    inittime!(s, st; stargs...)
    s
end
initname!(s::Statevar, st::State; name, alias=nothing, stargs...) = (s.name = name; s.alias = alias)
inittime!(s::Statevar, st::State; time, stargs...) = (s.time = time)
inittime!(s::Statevar, st::Tock; stargs...) = (s.time = s)

(s::Statevar)(args...) = s.calc(args...)

gettime!(s::Statevar{Tock}) = value(s.state)
gettime!(s::Statevar) = getvar!(s.time)

function getvar!(s::Statevar)
    t = gettime!(s)
    #println("check! for $s")
    if check!(s.state, t)
        #println("checked! let's getvar!")
        # https://discourse.julialang.org/t/extract-argument-names/862
        # https://discourse.julialang.org/t/retrieve-default-values-of-keyword-arguments/19320
        names = Base.uncompressed_ast(methods(s.calc).ms[end]).slotnames[2:end]
        # https://discourse.julialang.org/t/is-there-a-way-to-get-keyword-argument-names-of-a-method/20454
        # first.(Base.arg_decl_parts(m)[2][2:end])
        # Base.kwarg_decl(first(methods(f)), typeof(methods(f).mt.kwsorter))
        v = s.calc([getvar!(s.system, n) for n in names]...)
        setvar!(s, v)
    end
    value(s.state)
end
getvar!(s::System, n::Symbol) = getvar!(getfield(s, n))
function setvar!(s::Statevar, v)
    store!(s.state, v)
    #FIXME: implement context.queue
    poststore!(s.state, v)()
end

# import Base: convert, promote_rule
# convert(::Type{Float64}, s::Statevar) = getvar!(s)
# promote_rule(::Type{Statevar}, ::Type{Float64}) = Float64
# promote_rule(::Type{Statevar}, ::Type{Int64}) = Float64

import Base: show
show(io::IO, s::Statevar) = print(io, "$(s.system)<$(s.name)> = $(s.state.value)")

export System, Statevar, getvar!, setvar!
