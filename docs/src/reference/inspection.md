# [Inspection](@id Inspection1)

Inspection functions answer different questions about one model:

| Function | Question |
|---|---|
| `parameters` | What may configuration change, and what are the current/default values? |
| `look` | What does this system or variable declare? |
| `@look` | Can I write the same inspection in convenient property syntax? |
| `dive` | What is inside this constructed nested instance? |

Use the type when studying structure and an instance when current values
matter.

## `parameters`

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

- `alias=true` uses a descriptive alias when one exists.
- `recursive=true` follows declared child systems and includes their
  parameters.
- `exclude=(Context,)` or another type tuple omits infrastructure or a branch
  that should not be followed.
- `scope` selects the module in which type defaults and constants are
  evaluated. Its default is the module where the system was declared.

The type form can evaluate only a parameter default with no model-variable
dependencies. It reports a dependent or externally required default as
`missing`. The instance form reads current values, so it is the better choice
after configuration has been applied.

`recursive=true` follows types visible in declarations. A dynamically typed
vector of systems may not reveal every runtime child type; inspect a constructed
instance or use a model-specific hierarchy traversal in that case.

## Inspect declarations with `look`

```julia
look(SystemType)
look(instance)
look(SystemType, :variable)
look(instance, :variable)
look(Module, :SystemName)
```

For a system, `look` shows the system docstring and public declaration surface.
For a variable, it shows the variable docstring and normalized declaration
line. Supplying an instance also shows current values.

The display sections can be selected with keywords:

| Keyword | Applies to | Default | Meaning |
|---|---|---:|---|
| `header` | all forms | `true` | show section labels such as `[doc]` |
| `doc` | system or variable | `true` | show stored documentation |
| `system` | system summary | `true` | show fields and current values when available |
| `code` | variable on a type | `true` | show the declaration line |
| `value` | variable on an instance | `true` | show the current value |
| `excerpt` | variable documentation | `false` | show only its first documentation line |

These switches are useful when embedding inspection output in a notebook, but
they do not change the model. A declaration printed by `look` is the composed
result, which may differ from the source line in an earlier mixin.

## Use property syntax with `@look`

The macro supplies convenient property-like spelling:

```julia
@look Model
@look Model.variable
@look instance.variable
@look Model variable
```

The dotted forms with no call are equivalent to `look(Model, :variable)`.

A dotted call is intentionally different:

```julia
@look instance.response(25u"°C")
@look instance.response(; temperature = 25u"°C")
```

It calls `value(instance, :response, ...)` to evaluate a function-like
declaration body. It does not print declaration documentation. Use
`look(instance, :response)` when inspection, rather than evaluation, is the
goal.

## `dive`

```julia
dive(instance)
```

`dive` opens a terminal menu for walking through nested systems, state values,
and vectors of systems. Use the arrow keys to select an item, Enter to descend,
and `q` to move back. A leaf first displays `look`; pressing Enter again returns
that object to the REPL.

The menu needs a real terminal. In an initialized IJulia session, `dive`
falls back to the noninteractive `look(instance)` summary. In notebooks and
scripts, explicit property paths and `look` are easier to reproduce.

## Dependency debugging

`Cropbox.dependency(SystemType)` exposes the graph used while generating update
order. It is intentionally not exported and its node representation is not a
stable serialization format. Package authors can use it to diagnose cycles or
stage ordering; model documentation should describe the scientific dependency
chain in plain language instead.
