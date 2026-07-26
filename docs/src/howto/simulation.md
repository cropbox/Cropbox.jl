# [Run Simulations and Shape Output](@id simulation-workflow)

`simulate` combines instance construction, repeated updates, snapshots, and
DataFrame formatting. Most options belong to one of those four jobs.

## A minimal simulation

```@example simflow
using Cropbox

@system OutputDemo(Controller) begin
    rate              => 2          ~ preserve(parameter, u"m/hr")
    distance(rate)                  ~ accumulate(u"m")
    squared(distance) => distance^2 ~ track(u"m^2")
end

simulate(OutputDemo; stop = 3u"hr")
```

Without `stop`, `snap`, `snatch`, or `callback`, `simulate` returns a snapshot of
the initialized instance rather than advancing indefinitely.

## Select columns

The default index is the clock time and the default target includes most simple
variables in the root system. Explicit output is faster and more stable.

```@example simflow
simulate(OutputDemo;
    stop = 3u"hr",
    index = :hour => "context.clock.time",
    target = [:distance, :squared],
)
```

Output selectors accept:

- a symbol for a root variable;
- a string path such as `"calendar.date"`;
- a pair `:column_name => "system.path"`;
- a vector or tuple of selectors;
- `"*"` or `"child.*"` to expand available fields.

Wildcard output is convenient for exploration but should be replaced with an
explicit list in long-running studies.

Output extraction accepts scalar numbers, symbols, strings, and date/time
values. A vector, dictionary, tuple, or other complex object is omitted even
when named explicitly in `target`. Summarize it in a scalar declaration or use
`snatch` when the object itself determines custom output.

## Choose a base system

`base` makes `index` and `target` relative to a nested system or bundle. This is
useful when a root controller mainly coordinates another component.

```julia
simulate(Model;
    base = :plant,
    index = "calendar.date",
    target = [:LAI, :biomass],
    stop = :mature,
)
```

Without `base`, full string paths can reach the same values.

## Add scenario metadata

`meta` copies configuration values into the output.

```@example simflow
configs = @config !(OutputDemo => :rate => [1, 2, 3])

simulate(OutputDemo;
    configs,
    stop = 2u"hr",
    target = :distance,
    meta = [:OutputDemo],
)
```

A system name such as `:OutputDemo` copies its configuration entries into the
output. A pair such as `:replicate => 1` adds an arbitrary constant metadata
column. Keep metadata small: copying all parameters into a long simulation can
make output unnecessarily wide.

## Apply a shared base to scenarios

When every treatment shares infrastructure or initial conditions, pass the
shared configuration as `config` and treatment patches as `configs`. Each patch
is merged after the base and can override it.

```@example simflow
base = @config (
    OutputDemo => :rate => 1,
    Clock => :step => 30u"minute",
)

treatments = @config !(OutputDemo => :rate => [2, 3])

simulate(OutputDemo;
    config = base,
    configs = treatments,
    stop = 2u"hr",
    target = :distance,
    meta = [:OutputDemo],
)
```

Build fully merged configurations in advance when they will be saved, reviewed,
or reused by several APIs. The shared-base form is convenient when the patches
are local to one simulation call.

## Control snapshots

```julia
simulate(Model; stop = 100u"d", snap = 1u"d")
simulate(Model; stop = :mature, snap = :emerged)
simulate(Model; stop = :mature, snap = s -> s.calendar.date' in dates)
```

The model still updates at `Clock.step`; `snap` only controls output frequency.
It is tested for the initialized state and after every update. Use it as the
first tool for reducing memory and plotting overhead.

## Custom output with `snatch`

The `snatch` callback receives the rows extracted for the current snapshot and
the current instance. A do-block is a concise spelling.

```julia
result = simulate(RootArchitecture; config, options, seed, stop) do rows, s
    rows[1][:root_count] = length(s.roots')
end
```

The callback may edit or empty `rows`. This is an advanced escape hatch for
non-scalar model structures. Prefer ordinary `target` selectors when possible.

`callback` runs after the snapshot has been updated and receives the instance
and internal simulation layout. It is lower level than `snatch`; use it only
when the output callback itself must coordinate external work.

## Format the DataFrame

- `nounit=true` removes units from returned columns; it does not disable units
  inside the model.
- `long=true` stacks target columns into a long table.
- `verbose=false` suppresses the progress display.

```@example simflow
simulate(OutputDemo;
    stop = 2u"hr",
    target = [:distance, :squared],
    nounit = true,
    long = true,
    verbose = false,
)
```

Long format creates more rows and is best requested only when a downstream
analysis or plotting tool needs it.

## Fresh versus reused instances

`simulate(SystemType; ...)` constructs a fresh instance. `simulate!(instance;
...)` mutates and continues an existing one. For independent replicates, create
fresh instances. For staged management or interactive control, deliberate reuse
with `simulate!` can avoid rebuilding an expensive model.

## Randomness and batches

`seed` is applied before configuration parsing and instance construction. This
also controls distributions written with `±`. In a batch of configurations, the
same seed is reset for each scenario. Use separate calls or explicit seed loops
when every replicate must receive an independent random stream.
