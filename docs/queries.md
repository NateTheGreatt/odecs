# Queries

## Basics

```odin
for arch in ecs.query(world, {Position, Velocity}) {
    positions := ecs.get_table(world, arch, Position)
    velocities := ecs.get_table(world, arch, Velocity)
    for i in 0..<len(arch.entities) {
        positions[i].x += velocities[i].vx * dt
        positions[i].y += velocities[i].vy * dt
    }
}
// Cleanup is automatic — safe to break/return early
```

Plain typeids are AND by default — `{Position, Velocity}` is equivalent to `{ecs.all(Position, Velocity)}`.

---

## Term Builders

```odin
// AND — all must be present (aliases: and, all)
ecs.query(world, {ecs.all(Position, Velocity)})

// OR — at least one must be present (aliases: or, some)
ecs.query(world, {ecs.or(Player, Enemy)})

// NOT — exclude entities with these (aliases: not, none)
ecs.query(world, {Position, ecs.not(Dead)})
ecs.query(world, {NPC, ecs.none(Dead, Hostile)})

// Pairs — see relationships.md
ecs.query(world, {ecs.pair(ChildOf, ecs.Wildcard)})

// Combining
ecs.query(world, {Position, ecs.or(Player, Enemy), ecs.not(Dead)})
ecs.query(world, {Vendor, ecs.or(ecs.pair(Sells, Potions), ecs.pair(Sells, Weapons))})
```

---

## Hierarchy / Cascade

Depth-ordered iteration — parents before children:

```odin
for arch in ecs.query(world, {ecs.hierarchy(ChildOf)}) {
    // Depth 0 (roots) first, then depth 1, etc.
}
```

`cascade` is an alias for `hierarchy`.

---

## Caching

Queries are automatically cached. Cache invalidates only when new archetypes are created (rare — happens when an entity gets a never-before-seen component combination). Invalidation is lazy: queries re-scan on next call, not immediately.

---

## Nested Queries

Nested queries automatically defer structural changes:

```odin
for arch1 in ecs.query(world, {Position}) {
    for arch2 in ecs.query(world, {Velocity}) {
        ecs.add_component(world, entity, NewComponent{})  // deferred
    }
}
// All deferred ops flush when outer query's scope exits
```

---

## Examples

### Finding First Match

```odin
find_first_healthy_npc :: proc(world: ^ecs.World, min_health: int) -> ecs.EntityID {
    for arch in ecs.query(world, {NPC, Health}) {
        entities := ecs.get_entities(arch)
        health_values := ecs.get_table(world, arch, Health)

        for i in 0..<len(arch.entities) {
            if health_values[i].value >= min_health {
                return entities[i]
            }
        }
    }

    return 0  // Not found
}
```

### Death System (Deferred Changes)

```odin
death_system :: proc(world: ^ecs.World) {
    for arch in ecs.query(world, {Health, ecs.not(Dead)}) {
        entities := ecs.get_entities(arch)
        healths := ecs.get_table(world, arch, Health)

        for i in 0..<len(arch.entities) {
            if healths[i].current <= 0 {
                ecs.add_component(world, entities[i], Dead{})
            }
        }
    }
    // Changes auto-applied when query's scope exits
}
```
