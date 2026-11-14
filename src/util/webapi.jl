# Web API: JSON codec for Cropbox values, model description (`describe`) and
# the HTTP service (`serve`, `dashboard`). Static assets (OpenAPI document,
# Swagger UI page, bundled dashboard) live next to the sources in `webapi/`.
include("webapi/codec.jl")
include("webapi/describe.jl")
include("webapi/service.jl")
