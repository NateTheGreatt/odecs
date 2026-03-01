# Observers in odecs

## What Are Observers?

Observers are a reactive system that fires callbacks when entities enter or leave specific archetype configurations. Instead of polling for changes, observers respond immediately when component changes occur.

**Use observers when you need to:**
- React to entity state changes (death, power-ups, status effects)
- Trigger side effects without polling (spawn effects, play sounds)
- Keep game logic decoupled from state transitions
- Track lifecycle events

---

## on_add and on_remove Events

### on_add Events

Fires when an entity **enters** an archetype configuration:

```odin
ecs.on_add(terms: ..Term) -> Observer_Def
```

Triggers when:
- Entity gains a component satisfying the observer's requirements
- Entity loses an excluded component

### on_remove Events

Fires when an entity **leaves** an archetype configuration:

```odin
ecs.on_remove(terms: ..Term) -> Observer_Def
```

Triggers when:
- Entity loses a required component
- Entity gains an excluded component
- Entity is destroyed

---

## Creating Observers

```odin
observe :: proc(
    world: ^World,
    def: Observer_Def,
    callback: proc(world: ^World, entity: EntityID)
) -> ObserverID
```

**Example:**

```odin
on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    fmt.println("Entity died:", entity)
}

obs := ecs.observe(world, ecs.on_add(ecs.all(Dead)), on_death)
defer ecs.unobserve(world, obs)
```

---

## Observer Callbacks

Callbacks receive the world and triggering entity:

```odin
proc(world: ^World, entity: EntityID)
```

**Accessing Game State (Odin pattern):**

Since Odin doesn't have closures, use a global pointer:

```odin
g_game: ^Game = nil

setup_observers :: proc(game: ^Game) {
    g_game = game
    ecs.observe(game.world, ecs.on_add(ecs.all(Dead)), on_death)
}

on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    game := g_game
    if game == nil do return

    game.kills += 1

    if pos := ecs.get_component(world, entity, Position); pos != nil {
        spawn_explosion(game, pos.x, pos.y)
    }
}
```

---

## Unregistering Observers

```odin
ecs.unobserve(world: ^World, id: ObserverID)
```

**Example:**

```odin
observer_id := ecs.observe(world, ecs.on_add(ecs.all(Dead)), on_death)

// Later
ecs.unobserve(world, observer_id)
```

---

## Common Observer Patterns

### Basic Lifecycle Events

```odin
ecs.observe(world, ecs.on_add(ecs.all(Position)), on_entity_spawn)
ecs.observe(world, ecs.on_remove(ecs.all(Position)), on_entity_despawn)
```

### Conditional Observers

```odin
// Fire only for entities with Position but NOT Velocity
ecs.observe(world, ecs.on_add(ecs.all(Position), ecs.not(Velocity)), on_static_spawn)
```

### Multiple Observers on Same Event

```odin
ecs.observe(world, ecs.on_add(ecs.all(Dead)), on_death_visual)
ecs.observe(world, ecs.on_add(ecs.all(Dead)), on_death_audio)
ecs.observe(world, ecs.on_add(ecs.all(Dead)), on_death_score)
```

### Entering via Component Removal

An entity can enter an observer's archetype by removing components:

```odin
// Register observer for (Position, !Velocity)
ecs.observe(world, ecs.on_add(ecs.all(Position), ecs.not(Velocity)), on_stopped)

// Removing Velocity from moving entity fires callback
ecs.remove_component(world, moving_entity, Velocity)
```

---

## Practical Examples

### Space Shooter Death System

```odin
g_game: ^Game = nil

setup_observers :: proc(game: ^Game) {
    g_game = game
    ecs.observe(game.world, ecs.on_add(ecs.all(Dead)), on_death)
}

on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    game := g_game
    if game == nil do return

    if ecs.has_component(world, entity, Player) {
        game.state = .GameOver
    } else if enemy := ecs.get_component(world, entity, Enemy); enemy != nil {
        game.score += enemy.points
        game.kills += 1

        if pos := ecs.get_component(world, entity, Position); pos != nil {
            spawn_explosion(game, pos.x, pos.y)
        }
    }
}
```

### Roguelike Death Handler

```odin
on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    game := g_game
    if game == nil do return

    // Remove movement blocking
    ecs.remove_component(world, entity, BlocksMovement)

    // Change visual to corpse
    if renderable := ecs.get_component(world, entity, Renderable); renderable != nil {
        renderable.glyph = '%'
        renderable.color = "\x1b[90m"
    }

    if ecs.has_component(world, entity, Player) {
        game.state = .GameOver
    } else {
        game.kills += 1
    }
}
```

### Shield Activation

```odin
ecs.observe(
    world,
    ecs.on_add(ecs.all(Shield), ecs.not(Damaged)),
    on_shield_activated
)

on_shield_activated :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    if shield := ecs.get_component(world, entity, Shield); shield != nil {
        fmt.println("Shield activated with", shield.hits_remaining, "hits")
    }
}
```

---

## Performance Notes

- Observers fire immediately during component add/remove
- Multiple observers on same event all fire
- Callbacks should be fast (part of mutation path)
- Use `unobserve()` to clean up when no longer needed
