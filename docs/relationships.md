# Relationships (Pairs)

Pairs express connections between entities. A pair reads like a sentence: **"entity [Relation] target"**.

## Tag Pairs

No data, just the relationship:

```odin
ChildOf :: distinct struct {}

parent := ecs.add_entity(world)
child := ecs.add_entity(world)

ecs.add_pair(world, child, ChildOf, parent)
ecs.has_pair(world, child, ChildOf, parent)  // -> true
ecs.remove_pair(world, child, ChildOf, parent)
```

## Data Pairs

Carry data along with the relationship:

```odin
Contains :: struct { amount: int, durability: f32 }

chest := ecs.add_entity(world)
gold := ecs.add_entity(world)

ecs.add_pair(world, chest, Contains{amount = 50, durability = 100.0}, gold)

if data := ecs.get_pair(world, chest, Contains, gold); data != nil {
    fmt.println("Amount:", data.amount)
    data.amount += 10  // modify in place
}
```

## Relation Traits

Attach traits to relation types to control behavior:

```odin
ChildOf :: distinct struct {}

// Exclusive — entity can have only one target per relation
// Adding a new parent auto-removes the old one
ecs.add_component(world, ChildOf, Exclusive)

// Cascade — deleting the target deletes all entities with the pair
// e.g. deleting parent deletes all children
ecs.add_component(world, ChildOf, Cascade)
```

---

## Querying

```odin
// All children of anything
ecs.query(world, {ecs.pair(ChildOf, ecs.Wildcard)})

// Children of a specific parent
ecs.query(world, {ecs.pair(ChildOf, parent)})

// Combine with components
ecs.query(world, {Position, ecs.pair(ChildOf, ecs.Wildcard)})

// Exclude relationships
ecs.query(world, {Position, ecs.not(ecs.pair(ChildOf, ecs.Wildcard))})
```

---

## Common Patterns

### Hierarchy

```odin
ChildOf :: distinct struct {}

parent := ecs.add_entity(world)
child1 := ecs.add_entity(world)
child2 := ecs.add_entity(world)

ecs.add_pair(world, child1, ChildOf, parent)
ecs.add_pair(world, child2, ChildOf, parent)

// All children of parent
for arch in ecs.query(world, {ecs.pair(ChildOf, parent)}) { ... }

// Orphans (no parent)
for arch in ecs.query(world, {ecs.not(ecs.pair(ChildOf, ecs.Wildcard))}) { ... }
```

### Inventory

```odin
Owns :: struct { since: i64, condition: f32 }

player := ecs.add_entity(world)
sword := ecs.add_entity(world)

ecs.add_pair(world, player, Owns{since = 0, condition = 1.0}, sword)

for arch in ecs.query(world, {ecs.pair(Owns, ecs.Wildcard)}) { ... }
```

### Classification

```odin
IsA :: distinct struct {}
HasTag :: distinct struct {}

sword := ecs.add_entity(world)
weapon_type := ecs.add_entity(world)
fire_tag := ecs.add_entity(world)

ecs.add_pair(world, sword, IsA, weapon_type)
ecs.add_pair(world, sword, HasTag, fire_tag)

// All fire weapons
for arch in ecs.query(world, {ecs.pair(IsA, weapon_type), ecs.pair(HasTag, fire_tag)}) { ... }
```
