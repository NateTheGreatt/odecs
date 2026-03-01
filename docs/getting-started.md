# Getting Started with odecs

## Your First ECS Program

### Define Components

```odin
// Data components
Position :: struct { x, y: f32 }
Velocity :: struct { vx, vy: f32 }
Health :: struct { current, max: i32 }

// Tag components (zero-sized markers)
Player :: distinct struct {}
Enemy :: distinct struct {}
Dead :: distinct struct {}
```

### Create World and Entities

```odin
world := ecs.create_world()
defer ecs.delete_world(world)

// Create entity with initial components
player := ecs.add_entity(world, Position{100, 150}, Velocity{0, 0}, Player{})
enemy := ecs.add_entity(world, Position{500, 150}, Velocity{-1, 0}, Enemy{})

// Or add components separately
bullet := ecs.add_entity(world)
ecs.add_component(world, bullet, Position{0, 0})
ecs.add_component(world, bullet, Velocity{10, 0})
```

### Query and Iterate

```odin
for arch in ecs.query(world, {Position, Velocity}) {
    positions := ecs.get_table(world, arch, Position)
    velocities := ecs.get_table(world, arch, Velocity)

    for i in 0..<len(arch.entities) {
        positions[i].x += velocities[i].vx
        positions[i].y += velocities[i].vy
    }
}
```

### Modify State

```odin
if health := ecs.get_component(world, player, Health); health != nil {
    health.current -= 10
}

ecs.has_component(world, player, Player)   // -> bool
ecs.remove_component(world, enemy, Velocity)
```

### Complete Example

```odin
package main

import "core:fmt"
import ecs "odecs/src"

Position :: struct { x, y: f32 }
Velocity :: struct { vx, vy: f32 }

main :: proc() {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    ecs.add_entity(world, Position{0, 0}, Velocity{1, 0})

    for i in 0..<3 {
        ecs.add_entity(world, Position{f32(i * 100), 0}, Velocity{-1, 0})
    }

    for frame in 0..<5 {
        for arch in ecs.query(world, {Position, Velocity}) {
            positions := ecs.get_table(world, arch, Position)
            velocities := ecs.get_table(world, arch, Velocity)

            for i in 0..<len(arch.entities) {
                positions[i].x += velocities[i].vx
            }
        }
        fmt.printf("Frame %d complete\n", frame)
    }
}
```

---

## Common Patterns

### Query with Excludes

```odin
for arch in ecs.query(world, {Position, Velocity, ecs.not(Dead)}) { ... }
```

### Observers

```odin
on_death :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    fmt.println("Entity died:", entity)
}

ecs.observe(world, ecs.on_add(Dead), on_death)
```

### System Ordering

```odin
system_input(world)
system_physics(world)
system_collision(world)
system_combat(world)
system_cleanup(world)
render(world)
// Each system's query auto-flushes deferred changes
```

Structural changes during iteration are automatically deferred — see `deferred-changes.md`.

