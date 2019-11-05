#HACK: Any seems to be faster than Function
struct Queue
    pre::Vector{Any}
    post::Vector{Any}
end

Queue() = Queue(Any[], Any[])

current(q::Queue, ::PrePriority) = q.pre
current(q::Queue, ::PostPriority) = q.post

queue!(q::Queue, f, p::Priority) = queue!(current(q, p), f)
queue!(q::Vector, f) = push!(q, f)
queue!(q::Vector, ::Nothing) = nothing

flush!(q::Queue, p::Priority) = flush!(current(q, p))
flush!(q::Vector) = (foreach(f -> f(), q); empty!(q))

preflush!(q::Queue) = flush!(q, PrePriority())
postflush!(q::Queue) = flush!(q, PostPriority())
