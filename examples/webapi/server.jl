#!/usr/bin/env julia
"""
Start an example dashboard and HTTP API on loopback.

    julia --project=examples/webapi examples/webapi/server.jl [cherry|gasexchange|garlic] [port]

Run from the repository root after preparing the example environment.
"""
function main(args=ARGS)
    length(args) <= 2 || throw(ArgumentError("expected a model name and optional port"))
    name = isempty(args) ? "cherry" : args[1]
    port = length(args) == 2 ? parse(Int, args[2]) : 8000
    1 <= port <= 65535 || throw(ArgumentError("port must be between 1 and 65535"))
    p = WebAPIExamples.profile(name)
    @info "Cropbox service" model=name dashboard="http://127.0.0.1:$port/dashboard" api="http://127.0.0.1:$port/api/model"
    Cropbox.serve(p.system; p.config, p.ui, p.request_defaults, port)
end

using Cropbox
include("profiles.jl")
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
