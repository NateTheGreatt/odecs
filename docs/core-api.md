# odecs Core API

## World

```odin
world := ecs.create_world()
defer ecs.delete_world(world)
```

`create_world` accepts optional `allocator` and `cache_allocator` parameters (both default to `context.allocator`). The `cache_allocator` is separate so the query cache can survive arena snapshot/rollback (e.g. GGPO).

`flush(world)` manually applies pending deferred ops. Rarely needed — query iteration auto-flushes.

---

## Entities

```odin
// Create with optional initial components
player := ecs.add_entity(world, Position{0, 0}, Velocity{1, 0}, Player{})
bullet := ecs.add_entity(world)

// Check / remove
if ecs.entity_alive(world, player) { ... }
ecs.remove_entity(world, bullet)  // deferred if called during iteration
```

---

## Components

```odin
// Add
ecs.add_component(world, entity, Position{10, 20})
ecs.add_components(world, entity, Position{0, 0}, Velocity{1, 0})  // single archetype transition

// Get (returns pointer, nil if missing)
if pos := ecs.get_component(world, entity, Position); pos != nil {
    pos.x += 1
}

// Check / remove
ecs.has_component(world, entity, Velocity)  // -> bool
ecs.remove_component(world, entity, Velocity)

// Disable/enable (stays in memory, just flagged)
ecs.disable_component(world, entity, Velocity)
ecs.is_component_disabled(world, entity, Velocity)  // -> bool
ecs.enable_component(world, entity, Velocity)
```

---

## Queries

```odin
for arch in ecs.query(world, {Position, Velocity}) {
    positions := ecs.get_table(world, arch, Position)
    velocities := ecs.get_table(world, arch, Velocity)

    for i in 0..<len(arch.entities) {
        positions[i].x += velocities[i].vx
    }
}
```

See `queries.md` for term builders (`not`, `or`, `pair`, `hierarchy`, etc.).

---

## Observers

```odin
on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    fmt.println("Entity died:", entity)
}

obs := ecs.observe(world, ecs.on_add(Dead), on_death)
ecs.unobserve(world, obs)
```

---

## Type Reference

```odin
EntityID    :: distinct u64    // 48-bit index, 16-bit generation
ComponentID :: distinct u32
ArchetypeID :: distinct u64
ObserverID  :: distinct u32
Wildcard    : Wildcard_T : {}  // matches any pair target
```
