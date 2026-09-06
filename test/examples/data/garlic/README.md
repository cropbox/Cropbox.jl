# Garlic weather CSV fixture

`cuh_2014_weather.csv` is the normalized CSV input used by the Garlic Web API
example. It contains the timestamp and four weather columns consumed by
`Garlic.Weather`.

The source data are distributed with
[Garlic.jl v0.1.29](https://github.com/cropbox/Garlic.jl/tree/v0.1.29)
as `data/CUH/2014.wea`, under that package's MIT license. Run
`convert.jl` in an environment containing Garlic to reproduce the CSV. The
conversion is an offline preparation step. The dashboard and HTTP examples read
only the generated CSV.
