# Observers

Observers fire callbacks when entities enter or leave archetype configurations. Use them for **side effects only** (logging, audio, particles, debug) — not game logic. Game logic belongs in systems (queries).

## on_add / on_remove

```odin
// Fires when entity gains Dead component
ecs.observe(world, ecs.on_add(Dead), on_death)

// Fires when entity loses Position (or is destroyed)
ecs.observe(world, ecs.on_remove(Position), on_despawn)

// Conditional — fires when entity has Position but loses Velocity
ecs.observe(world, ecs.on_add(Position, ecs.not(Velocity)), on_stopped)
```

`on_add` triggers when an entity enters the matching archetype (gains a required component or loses an excluded one). `on_remove` triggers when it leaves (loses a required component, gains an excluded one, or is destroyed).

---

## Callbacks

```odin
on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    // Side effects only — spawn particles, play sound, log, etc.
    if pos := ecs.get_component(world, entity, Position); pos != nil {
        spawn_explosion(pos.x, pos.y)
    }
}

obs := ecs.observe(world, ecs.on_add(Dead), on_death)
ecs.unobserve(world, obs)  // cleanup when no longer needed
```

Callbacks fire immediately during component add/remove and should be fast.

---

## Multiple Observers

```odin
ecs.observe(world, ecs.on_add(Dead), on_death_particles)
ecs.observe(world, ecs.on_add(Dead), on_death_audio)
```

All matching observers fire. Order is registration order.
