#HACK: Any seems to be faster than Function
struct ThreadedQueue
    pre::Vector{Any}
    post::Vector{Any}
end

struct Queue
    list::Vector{ThreadedQueue}
end

Queue() = begin
    n = Threads.nthreads()
    q = Vector{ThreadedQueue}(undef, n)
    for i in 1:n
        q[i] = ThreadedQueue()
    end
    Queue(q)
end
ThreadedQueue() = ThreadedQueue(Any[], Any[])

current(q::Queue) = q.list[Threads.threadid()]
current(q::Queue, p::Priority) = current(current(q), p)
current(q::ThreadedQueue, ::PrePriority) = q.pre
current(q::ThreadedQueue, ::PostPriority) = q.post

queue!(q::Queue, f, p::Priority) = queue!(current(q, p), f)
queue!(q::Vector, f) = push!(q, f)
queue!(q::Vector, ::Nothing) = nothing

flush!(q::Queue, p::Priority) = foreach(t -> flush!(current(t, p)), q.list)
flush!(q::Vector) = (foreach(f -> f(), q); empty!(q))

preflush!(q::Queue) = flush!(q, PrePriority())
postflush!(q::Queue) = flush!(q, PostPriority())
