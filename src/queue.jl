#HACK: Any seems to be faster than Function
import DataStructures: OrderedDict
mutable struct BufferedQueue
    front::OrderedDict{State,Any}
    back::OrderedDict{State,Any}
end

BufferedQueue() = BufferedQueue(OrderedDict{State,Any}(), OrderedDict{State,Any}())
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

queue!(q::Queue, s::State, f, p::Priority) = queue!(current(q, p), s, f)
queue!(q::BufferedQueue, s::State, f) = (q.front[s] = f)
queue!(q::BufferedQueue, ::State, ::Nothing) = nothing

flush!(q::Queue, p::Priority) = foreach(t -> flush!(current(t, p)), q.list)
flush!(q::BufferedQueue) = (b = flip!(q); foreach(f -> f(), values(b)); empty!(b))

preflush!(q::Queue) = flush!(q, PrePriority())
postflush!(q::Queue) = flush!(q, PostPriority())
