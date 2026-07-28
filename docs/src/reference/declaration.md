# [Declarations and Configuration](@id declaration-api)

Cropbox has two declaration macros. `@system` defines model structure;
`@config` describes values applied to that structure.

| Macro | Result | Use it for |
|---|---|---|
| `@system` | a subtype of `System` | variables, equations, behaviors, and composition |
| `@config` | one `Config` or a vector of them | parameters, scenario patches, sweeps, and factorial designs |

Neither macro runs a simulation. A system type is a reusable specification, and
a configuration is reusable input. `instance`, `simulate`, or `visualize`
brings the two together.

## `@system`

```text
@system Name[{patches...}][(mixins...)] [<: Supertype] begin
    # variable declarations...
end
```

The block may be omitted when the new system only combines mixins:

```julia
@system CropModel(Weather, Phenology, Growth, Controller)
```

`@system` parses the declarations, combines mixins from left to right, checks
behavior tags and dependencies, and generates the Julia system type and update
methods. A later mixin or local declaration can replace an earlier public
variable. Always inspect a heavily composed result with `look`.

The variable grammar is:

```text
name[(dependencies...; explicit_arguments...)][: alias] [=> body]
    ~ [behavior][::static_type|<:dynamic_type][(tags...)]
```

Read [DSL Syntax](@ref dsl-syntax) for every field in this grammar and
[Behaviors and Tags](@ref behaviors-and-tags) for accepted behavior options.
The generated type is ordinary Julia in the sense that it can be passed to
functions and used in type annotations, but its fields are Cropbox states and
must follow the Cropbox update lifecycle.

## `Config`

A `Config` is an ordered mapping from system name to parameter names and
values. The following parameter-list forms are equivalent:

```julia
@config Model => (:rate => 2, :initial => 3)
@config Model => (rate = 2, initial = 3)
```

`Config()` and `@config()` create an empty configuration. A value can be read
with `config[:Model][:rate]`; `length`, iteration, and equality follow the usual
Julia collection conventions. Combine configurations with
`@config base + patch`. Treat a completed configuration as experiment input rather than
mutating its nested mapping in place. Build a later patch and merge it when a
value changes.

Parameter values may be scalars, arrays, tables, functions, or other objects
accepted by the declaration. A value is not expanded merely because it is a
collection; expansion happens only through the `@config` sweep syntax.

`missing` means “no configured override” during parameter construction, so
Cropbox falls back to the declaration body. It is not stored as the parameter
value. For a `preserve(optional)` declaration whose intentional value is
absent, configure `nothing` instead.

### System keys and validation

Prefer the system type when it is available:

```julia
@config Model => :rate => 2
```

Cropbox then checks the short name or alias against parameters declared by
`Model` and applies the declared unit to a plain number. An explicitly unitful
value is converted when its dimension is compatible. A symbol such as `:Model`
or a string path such as `"Model.rate"` is normalized by name but cannot offer
the same early validation. Name-based keys are still useful for external files
or code that runs before the model package is loaded.

The special key `:0` means the executable root system. It is useful in generic
components and old workshop material whose root type is not known in advance.
Prefer the actual root type in maintained code because it is searchable and
validated.

### Merge order

Commas and `+` merge configurations from left to right. Later values win:

```julia
base = @config Model => (rate = 1, initial = 2)
patch = @config Model => :rate => 3

combined = @config base + patch
```

This rule also applies when the same parameter appears twice in one tuple. A
useful ordering is package defaults, cultivar or site settings, experiment
settings, and finally the treatment patch.

### One-factor expansion

Prefix `!` creates one configuration for each value in an iterable:

```julia
rates = @config !(Model => :rate => [1, 2, 3])
```

It returns `Vector{Config}` even when the iterable has one value. A literal
vector creates a hand-written scenario list without expansion:

```julia
scenarios = @config [
    Model => (rate = 1, initial = 0),
    Model => (rate = 3, initial = 10),
]
```

Pass either result as `configs`, not as `config`.

### Factorial expansion

Infix `*` creates a Cartesian product of factors:

```julia
design = @config (
    Model => :rate => [1, 2]
) * (
    Model => :initial => [0, 10]
)
```

The example produces four configurations in a stable nested-product order.
Parentheses matter because Julia's pair and arithmetic operators have different
precedence. Use `!` for one varying factor and `*` when every combination is
intended.

## `parameters`

`parameters` is the safest way to discover the configuration surface before
writing a patch:

```julia
parameters(SystemType;
    alias = false,
    recursive = false,
    exclude = (),
    scope = nothing,
)

parameters(instance;
    alias = false,
    recursive = false,
    exclude = (),
)
```

The type form evaluates dependency-free defaults; a default that depends on
another variable is reported as `missing`. The instance form reports the
current configured values. `recursive=true` follows nested system types;
`exclude` prevents unwanted infrastructure or already visited types from being
included. `scope` controls where a type form evaluates constants and defaults
and normally needs no override.

Aliases are convenient for reading, but short declared names are usually more
stable in saved configuration. Check both when adapting an older notebook.

## Configuration consumers

| Consumer | Configuration behavior |
|---|---|
| `instance` | one `config` |
| `simulate` | one `config`, many `configs`, or a shared `config` plus patches |
| `visualize` | one base `config` plus method-specific sweeps or groups |
| `evaluate` | either `config` or `configs`, not both |
| `calibrate` | either `config` or complete environment `configs`, not both |

`options` is separate from configuration. It passes constructor resources such
as an external geometric container. Prefer configuration for declared model
parameters so the experiment can be inspected and saved.

## API docstrings

```@docs
Config
@system
@config
parameters
```
