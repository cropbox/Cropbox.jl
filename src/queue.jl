#HACK: Any seems to be faster than Function
mutable struct BufferedQueue
    front::Vector{Any}
    back::Vector{Any}
end

BufferedQueue() = BufferedQueue(Any[], Any[])
flip!(q::BufferedQueue) = begin
    q.front, q.back = q.back, q.front
    q.back
end

struct ThreadedQueue
    pre::BufferedQueue
    post::BufferedQueue
end

ThreadedQueue() = ThreadedQueue(BufferedQueue(), BufferedQueue())

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

current(q::Queue) = q.list[Threads.threadid()]
current(q::Queue, p::Priority) = current(current(q), p)
current(q::ThreadedQueue, ::PrePriority) = q.pre
current(q::ThreadedQueue, ::PostPriority) = q.post

queue!(q::Queue, f, p::Priority) = queue!(current(q, p), f)
queue!(q::BufferedQueue, f) = push!(q.front, f)
queue!(q::BufferedQueue, ::Nothing) = nothing

flush!(q::Queue, p::Priority) = foreach(t -> flush!(current(t, p)), q.list)
flush!(q::BufferedQueue) = (b = flip!(q); foreach(f -> f(), b); empty!(b))

preflush!(q::Queue) = flush!(q, PrePriority())
postflush!(q::Queue) = flush!(q, PostPriority())
