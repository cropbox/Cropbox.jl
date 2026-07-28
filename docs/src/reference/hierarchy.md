# [Dynamic Hierarchies](@id dynamic-hierarchies)

Most Cropbox systems have a fixed composition. Some models instead create child
systems during a run, such as leaves, roots, or other organs. This page covers
the public APIs for creating those children and traversing the hierarchy that
exists at a particular time. For fixed composition, see
[Systems and Composition](@ref system).

## Create child systems with `produce`

The helper and the behavior have the same name but different jobs:

```julia
produce(ChildSystem; constructor_keywords...)  # production request
children => produce(ChildSystem) ~ produce      # declaration behavior
```

The helper makes a request. During the following production stage, Cropbox
constructs the child with the parent's context and any supplied keywords. A
vector-typed production appends children; a single-system production creates
at most one child. This distinction comes from `~ produce::Child[]` versus
`~ produce::Child`; the internal `single` tag is inferred from that type.
`produce(nothing)` makes no request, which is useful for a conditional body.
The `when` tag is the clearer choice when production depends on a Cropbox flag.

Produced children are updated as part of the parent hierarchy. Their number and
shape can change during a run, so ordinary scalar simulation output cannot
store the whole structure. Summarize it with `snatch`, or traverse it at chosen
snapshots with `gather!`. See [`produce`](@ref behavior-produce) for the
declaration behavior and its tags.

## Traverse a hierarchy with `Gather`

```julia
gather!(root, TargetSystemTypes...;
    store = [],
    callback = visit!,
    kwargs = (),
)

Gather(TargetSystemTypes, store, callback)
gather!(gather, value; keyword_context...)
visit!(gather, value; keyword_context...)
```

`visit!` recursively follows system fields and vectors of systems. `gather!`
dispatches the callback with `(gather, value, Val(:MatchedType))`; unmatched
values receive `Val(nothing)`. A collecting callback usually has one matching
method and one fallback:

```julia
function collect_roots!(g::Gather, root::BaseRoot, ::Val{:BaseRoot})
    push!(g, root)
    visit!(g, root)
end

collect_roots!(g::Gather, value, _) = visit!(g, value)

roots = gather!(architecture, BaseRoot;
    callback = collect_roots!,
)
```

The fallback is important because it continues walking through containers that
do not themselves match the requested type. After collection, `value(g)`,
`g[]`, and `g'` return the underlying store. `push!` and `append!` on the
`Gather` forward to that store, so it may be a vector or another compatible
accumulator.

The default callback traverses but does not decide what to collect. Model
packages such as CropRootBox therefore provide their own callbacks. Reuse a
`Gather` object when several traversals should append into one store; create a
new one for independent summaries.

## Where these APIs appear

| Need | API | Worked example |
|---|---|---|
| create dynamic child systems | `produce` | behavior reference and CropRootBox |
| summarize a hierarchy | `Gather`, `gather!`, `visit!` | CropRootBox tutorial |

The [CropRootBox tutorial](@ref croprootbox-tutorial) shows stochastic
production, traversal in a simulation callback, and geometry export from a
changing root architecture.
