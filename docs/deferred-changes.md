## Deferred Structural Changes

Structural changes (add/remove component, destroy entity) during query iteration are **deferred** until the query's enclosing scope exits. This is handled by `@(deferred_in)` on `query()`.

```odin
{
    for arch in query(world, {Position, Health}) {
        entities := get_entities(arch)
        healths := get_table(world, arch, Health)
        for i in 0..<len(arch.entities) {
            if healths[i].hp <= 0 {
                remove_entity(world, entities[i])  // deferred
            }
        }
    }
    // loop is done, but deferred ops have NOT flushed yet
}
// scope exits here — deferred ops flush now
```

In practice, if each system is a proc with one query, the proc body *is* the scope — so changes flush when the proc returns.

Manual `flush(world)` is only needed if you access entity structure (e.g. `get_component`, `has_component`) after a query but within the same scope. Alternatively, the next `query()` call auto-flushes pending ops before iterating.

## Systems as Procs

```odin
move_system :: proc(world: ^World) {
    for arch in query(world, {Position, Velocity}) {
        // ...
    }
}  // query scope exits, deferred ops flush

damage_system :: proc(world: ^World) {
    for arch in query(world, {Health}) {
        // ...
    }
}  // flush
```

No scheduler needed — just call procs in order in your game loop.
