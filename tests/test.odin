package tests

import ecs "../src"

import "core:testing"
import "core:fmt"

// Test components
Position :: struct {
    x, y: f32,
}

Velocity :: struct {
    x, y: f32,
}

Health :: struct {
    value: int,
}

Contains :: struct {
    amount: int,
}

Gold :: distinct struct {}
Dead :: distinct struct {}

// =============================================================================
// ENTITY TESTS
// =============================================================================

@(test)
test_entity_create_destroy :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    e2 := ecs.add_entity(world)
    e3 := ecs.add_entity(world)

    testing.expect(t, ecs.entity_alive(world, e1), "e1 should be alive")
    testing.expect(t, ecs.entity_alive(world, e2), "e2 should be alive")
    testing.expect(t, ecs.entity_alive(world, e3), "e3 should be alive")

    ecs.remove_entity(world, e2)

    testing.expect(t, ecs.entity_alive(world, e1), "e1 should still be alive")
    testing.expect(t, !ecs.entity_alive(world, e2), "e2 should be dead")
    testing.expect(t, ecs.entity_alive(world, e3), "e3 should still be alive")
}

@(test)
test_entity_recycling :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    old_index := ecs.entity_index(e1)
    old_gen := ecs.entity_generation(e1)

    ecs.remove_entity(world, e1)
    testing.expect(t, !ecs.entity_alive(world, e1), "e1 should be dead after destroy")

    // Create new entity - should recycle the slot
    e2 := ecs.add_entity(world)
    new_index := ecs.entity_index(e2)
    new_gen := ecs.entity_generation(e2)

    testing.expect(t, new_index == old_index, "Should recycle same index")
    testing.expect(t, new_gen == old_gen + 1, "Generation should be bumped")

    // Old entity ID should still be invalid
    testing.expect(t, !ecs.entity_alive(world, e1), "Old entity ID should still be invalid")
    testing.expect(t, ecs.entity_alive(world, e2), "New entity ID should be valid")
}

@(test)
test_entity_aliases :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    testing.expect(t, ecs.entity_alive(world, e), "entity_exists should work")

    ecs.remove_entity(world, e)
    testing.expect(t, !ecs.entity_alive(world, e), "entity should not exist after remove")
}

// =============================================================================
// COMPONENT TESTS
// =============================================================================

@(test)
test_add_get_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{10, 20})

    pos := ecs.get_component(world, e, Position)
    testing.expect(t, pos != nil, "Should get position")
    testing.expect(t, pos.x == 10, "Position x should be 10")
    testing.expect(t, pos.y == 20, "Position y should be 20")
}

@(test)
test_has_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    testing.expect(t, !ecs.has_component(world, e, Position), "Should not have Position yet")

    ecs.add_component(world, e, Position{1, 2})
    testing.expect(t, ecs.has_component(world, e, Position), "Should have Position now")

    ecs.remove_component(world, e, Position)
    testing.expect(t, !ecs.has_component(world, e, Position), "Should not have Position after remove")
}

@(test)
test_component_update :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Health{100})

    h := ecs.get_component(world, e, Health)
    testing.expect(t, h.value == 100, "Health should be 100")

    // Update via add_component (should overwrite)
    ecs.add_component(world, e, Health{50})
    h = ecs.get_component(world, e, Health)
    testing.expect(t, h.value == 50, "Health should be 50 after update")
}

@(test)
test_multiple_components :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})
    ecs.add_component(world, e, Velocity{3, 4})
    ecs.add_component(world, e, Health{100})

    testing.expect(t, ecs.has_component(world, e, Position), "Should have Position")
    testing.expect(t, ecs.has_component(world, e, Velocity), "Should have Velocity")
    testing.expect(t, ecs.has_component(world, e, Health), "Should have Health")

    pos := ecs.get_component(world, e, Position)
    vel := ecs.get_component(world, e, Velocity)
    hp := ecs.get_component(world, e, Health)

    testing.expect(t, pos.x == 1 && pos.y == 2, "Position values correct")
    testing.expect(t, vel.x == 3 && vel.y == 4, "Velocity values correct")
    testing.expect(t, hp.value == 100, "Health value correct")
}

@(test)
test_tag_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Dead{})

    testing.expect(t, ecs.has_component(world, e, Dead), "Should have Dead tag")

    ecs.remove_component(world, e, Dead)
    testing.expect(t, !ecs.has_component(world, e, Dead), "Should not have Dead tag after remove")
}

// =============================================================================
// BATCH COMPONENT TESTS
// =============================================================================

@(test)
test_add_components_batch :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)

    // Add multiple components at once
    ecs.add_components(world, e, Position{1, 2}, Velocity{3, 4}, Health{100})

    testing.expect(t, ecs.has_component(world, e, Position), "Should have Position")
    testing.expect(t, ecs.has_component(world, e, Velocity), "Should have Velocity")
    testing.expect(t, ecs.has_component(world, e, Health), "Should have Health")

    pos := ecs.get_component(world, e, Position)
    vel := ecs.get_component(world, e, Velocity)
    hp := ecs.get_component(world, e, Health)

    testing.expect(t, pos.x == 1 && pos.y == 2, "Position values correct")
    testing.expect(t, vel.x == 3 && vel.y == 4, "Velocity values correct")
    testing.expect(t, hp.value == 100, "Health value correct")
}

// =============================================================================
// COMPONENT ENABLE/DISABLE TESTS
// =============================================================================

@(test)
test_disable_enable_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Health{100})

    testing.expect(t, !ecs.is_component_disabled(world, e, Health), "Health should not be disabled initially")
    testing.expect(t, ecs.is_component_enabled(world, e, Health), "Health should be enabled initially")

    ecs.disable_component(world, e, Health)
    testing.expect(t, ecs.is_component_disabled(world, e, Health), "Health should be disabled")
    testing.expect(t, !ecs.is_component_enabled(world, e, Health), "Health should not be enabled")

    // Component should still exist
    testing.expect(t, ecs.has_component(world, e, Health), "Should still have Health component")

    // Can still get it
    hp := ecs.get_component(world, e, Health)
    testing.expect(t, hp != nil && hp.value == 100, "Should still get Health value")

    ecs.enable_component(world, e, Health)
    testing.expect(t, !ecs.is_component_disabled(world, e, Health), "Health should not be disabled after enable")
    testing.expect(t, ecs.is_component_enabled(world, e, Health), "Health should be enabled after enable")
}

// =============================================================================
// QUERY TESTS
// =============================================================================

@(test)
test_basic_query :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    ecs.add_component(world, e2, Velocity{1, 1})

    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Velocity{3, 3})

    // Query Position only
    result := ecs.query_raw(world, {ecs.all(Position)})
    testing.expect(t, len(result) == 2, "Should have 2 archetypes with Position")

    total_entities := 0
    for arch in result {
        total_entities += len(ecs.get_entities(arch))
    }
    testing.expect(t, total_entities == 2, "Should have 2 entities with Position")
}

@(test)
test_query_with_not :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    ecs.add_component(world, e2, Dead{})

    // Query Position but NOT Dead
    result := ecs.query_raw(world, {ecs.all(Position), ecs.not(ecs.all(Dead))})

    total_entities := 0
    for arch in result {
        total_entities += len(ecs.get_entities(arch))
    }
    testing.expect(t, total_entities == 1, "Should have 1 entity with Position but not Dead")
}

@(test)
test_query_iterator :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<10 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i * 2)})
    }

    count := 0
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for entity, arch, row in ecs.query_next(&iter) {
        pos := ecs.get_component_from_archetype(world, arch, row, Position)
        testing.expect(t, pos != nil, "Should get position from iterator")
        count += 1
    }

    testing.expect(t, count == 10, "Should iterate over 10 entities")
}

@(test)
test_get_table :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<5 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i * 10)})
    }

    for arch in ecs.query(world, {ecs.all(Position)}) {
        positions := ecs.get_table(world, arch, Position)
        entities := ecs.get_entities(arch)

        testing.expect(t, len(positions) == 5, "Should have 5 positions")
        testing.expect(t, len(entities) == 5, "Should have 5 entities")

        // Verify data
        for pos, i in positions {
            testing.expect(t, pos.x == f32(i), fmt.tprintf("Position[%d].x should be %d", i, i))
            testing.expect(t, pos.y == f32(i * 10), fmt.tprintf("Position[%d].y should be %d", i, i * 10))
        }
    }
}

// =============================================================================
// PAIR/RELATIONSHIP TESTS
// =============================================================================

@(test)
test_pair_types :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)

    // Add pair with data
    ecs.add_pair(world, e, Contains{amount = 50}, Gold)

    testing.expect(t, ecs.has_pair(world, e, Contains, Gold), "Should have Contains-Gold pair")

    // Get pair data
    contains := ecs.get_pair(world, e, Contains, Gold)
    testing.expect(t, contains != nil, "Should get Contains data")
    testing.expect(t, contains.amount == 50, "Contains amount should be 50")

    // Remove pair
    ecs.remove_pair(world, e, Contains, Gold)
    testing.expect(t, !ecs.has_pair(world, e, Contains, Gold), "Should not have pair after remove")
}

@(test)
test_pair_with_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    gold_item := ecs.add_entity(world)
    player := ecs.add_entity(world)

    // Player contains gold_item
    ecs.add_pair(world, player, Contains{amount = 10}, gold_item)

    testing.expect(t, ecs.has_pair(world, player, Contains, gold_item), "Player should have Contains-gold_item pair")

    contains := ecs.get_pair(world, player, Contains, gold_item)
    testing.expect(t, contains != nil && contains.amount == 10, "Should get Contains data")

    // Remove
    ecs.remove_pair(world, player, Contains, gold_item)
    testing.expect(t, !ecs.has_pair(world, player, Contains, gold_item), "Should not have pair after remove")
}

@(test)
test_query_pairs :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    gold := ecs.add_entity(world)

    for i in 0..<5 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i)})
        if i % 2 == 0 {
            ecs.add_pair(world, e, Contains{amount = i}, gold)
        }
    }

    // Query entities with Contains-gold pair
    total := 0
    for arch in ecs.query(world, {ecs.pair(Contains, gold)}) {
        total += len(ecs.get_entities(arch))
    }
    testing.expect(t, total == 3, "Should have 3 entities with Contains-gold (i=0,2,4)")

    // Query entities with Position but NOT Contains-gold
    total2 := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.not(ecs.pair(Contains, gold))}) {
        total2 += len(ecs.get_entities(arch))
    }
    testing.expect(t, total2 == 2, "Should have 2 entities with Position but not Contains-gold (i=1,3)")
}

// =============================================================================
// ARCHETYPE TESTS
// =============================================================================

@(test)
test_archetype_transitions :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)

    // Start with no components (empty archetype)
    arch1 := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch1 != nil, "Should have empty archetype")

    // Add Position -> new archetype
    ecs.add_component(world, e, Position{1, 2})
    arch2 := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch2 != arch1, "Should be in different archetype after add")

    // Add Velocity -> another new archetype
    ecs.add_component(world, e, Velocity{3, 4})
    arch3 := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch3 != arch2, "Should be in different archetype after second add")

    // Remove Position -> yet another archetype
    ecs.remove_component(world, e, Position)
    arch4 := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch4 != arch3, "Should be in different archetype after remove")

    // Verify remaining components
    testing.expect(t, !ecs.has_component(world, e, Position), "Should not have Position")
    testing.expect(t, ecs.has_component(world, e, Velocity), "Should have Velocity")
}

@(test)
test_entity_row :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    entities: [5]ecs.EntityID
    for i in 0..<5 {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i)})
    }

    // All should be in same archetype
    for i in 0..<5 {
        row := ecs.get_entity_row(world, entities[i])
        testing.expect(t, row == i, fmt.tprintf("Entity %d should be at row %d", i, i))
    }
}

// =============================================================================
// HASH TESTS
// =============================================================================

@(test)
test_archetype_hash_order_independent :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create two entities with same components added in different order
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_component(world, e1, Velocity{2, 2})
    ecs.add_component(world, e1, Health{100})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Health{50})
    ecs.add_component(world, e2, Position{3, 3})
    ecs.add_component(world, e2, Velocity{4, 4})

    // Should be in same archetype
    arch1 := ecs.get_entity_archetype(world, e1)
    arch2 := ecs.get_entity_archetype(world, e2)
    testing.expect(t, arch1 == arch2, "Same components should result in same archetype regardless of add order")
}

// =============================================================================
// STRESS TESTS
// =============================================================================

@(test)
test_many_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    N :: 1000
    entities: [N]ecs.EntityID

    for i in 0..<N {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i * 2)})
        if i % 2 == 0 {
            ecs.add_component(world, entities[i], Velocity{1, 1})
        }
    }

    // Query Position
    count_pos := 0
    for arch in ecs.query(world, {ecs.all(Position)}) {
        count_pos += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_pos == N, fmt.tprintf("Should have %d entities with Position", N))

    // Query Position + Velocity
    count_both := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.all(Velocity)}) {
        count_both += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_both == N / 2, fmt.tprintf("Should have %d entities with Position+Velocity", N / 2))

    // Delete half
    for i in 0..<N/2 {
        ecs.remove_entity(world, entities[i])
    }

    count_remaining := 0
    for arch in ecs.query(world, {ecs.all(Position)}) {
        count_remaining += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_remaining == N / 2, fmt.tprintf("Should have %d entities remaining", N / 2))
}

// =============================================================================
// EDGE CASE: STALE/DEAD ENTITY OPERATIONS
// =============================================================================

@(test)
test_operations_on_dead_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})
    ecs.remove_entity(world, e)

    // All operations on dead entity should be safe (no crash) and return nil/false
    testing.expect(t, !ecs.entity_alive(world, e), "Dead entity should not be alive")
    testing.expect(t, ecs.get_component(world, e, Position) == nil, "get_component on dead entity should return nil")
    testing.expect(t, !ecs.has_component(world, e, Position), "has_component on dead entity should return false")
    testing.expect(t, ecs.get_entity_row(world, e) == -1, "get_entity_row on dead entity should return -1")
    testing.expect(t, ecs.get_entity_archetype(world, e) == nil, "get_entity_archetype on dead entity should return nil")

    // These should be no-ops (no crash)
    ecs.add_component(world, e, Velocity{1, 1})
    ecs.remove_component(world, e, Position)
    ecs.disable_component(world, e, Position)
    ecs.enable_component(world, e, Position)
}

@(test)
test_operations_on_stale_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 2})

    old_entity := e1
    ecs.remove_entity(world, e1)

    // Create new entity (should recycle the slot with new generation)
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{3, 4})

    // Old entity ID should be stale
    testing.expect(t, !ecs.entity_alive(world, old_entity), "Stale entity should not be alive")
    testing.expect(t, ecs.entity_alive(world, e2), "New entity should be alive")

    // Operations on stale entity should not affect new entity
    testing.expect(t, ecs.get_component(world, old_entity, Position) == nil, "get_component on stale entity should return nil")

    // New entity should still have correct data
    pos := ecs.get_component(world, e2, Position)
    testing.expect(t, pos != nil && pos.x == 3 && pos.y == 4, "New entity data should be intact")
}

// =============================================================================
// EDGE CASE: NON-EXISTENT COMPONENTS
// =============================================================================

@(test)
test_get_nonexistent_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Get component that entity doesn't have
    vel := ecs.get_component(world, e, Velocity)
    testing.expect(t, vel == nil, "Getting non-existent component should return nil")

    // Get component that's not even registered
    Unregistered :: struct { x: int }
    unreg := ecs.get_component(world, e, Unregistered)
    testing.expect(t, unreg == nil, "Getting unregistered component should return nil")
}

@(test)
test_remove_nonexistent_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Remove component entity doesn't have (should be no-op)
    ecs.remove_component(world, e, Velocity)

    // Entity should still have Position
    testing.expect(t, ecs.has_component(world, e, Position), "Should still have Position after removing non-existent component")
}

// =============================================================================
// CAST OPERATIONS
// =============================================================================

@(test)
test_get_component_cast :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1.5, 2.5})

    // Cast Position to raw bytes/different struct
    Vec2 :: struct { a, b: f32 }
    vec := ecs.get_component_cast(world, e, Position, Vec2)
    testing.expect(t, vec != nil, "Should get cast component")
    testing.expect(t, vec.a == 1.5 && vec.b == 2.5, "Cast values should match")
}

@(test)
test_get_table_cast :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<3 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i * 2)})
    }

    Vec2 :: struct { x, y: f32 }

    for arch in ecs.query(world, {ecs.all(Position)}) {
        vecs := ecs.get_table_cast(world, arch, Position, Vec2)
        testing.expect(t, len(vecs) == 3, "Should have 3 items in cast table")
        for v, i in vecs {
            testing.expect(t, v.x == f32(i) && v.y == f32(i * 2), "Cast table values should match")
        }
    }
}

// =============================================================================
// MORE PAIR OPERATIONS
// =============================================================================

@(test)
test_pair_entity_as_relation :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    likes_relation := ecs.add_entity(world)  // "Likes" as an entity
    player := ecs.add_entity(world)
    npc := ecs.add_entity(world)

    // Player likes NPC (entity-entity pair)
    ecs.add_pair(world, player, likes_relation, npc)

    testing.expect(t, ecs.has_pair(world, player, likes_relation, npc), "Player should have Likes-NPC pair")

    // Query for entities that like the NPC - test for-in pattern
    count := 0
    for arch in ecs.query(world, {ecs.pair(likes_relation, npc)}) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity that likes NPC")

    ecs.remove_pair(world, player, likes_relation, npc)
    testing.expect(t, !ecs.has_pair(world, player, likes_relation, npc), "Should not have pair after remove")
}

@(test)
test_pair_entity_target_with_type_relation :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // TestRelation relationship (type as relation, entity as target)
    TestRelation :: distinct struct {}

    parent := ecs.add_entity(world)
    child1 := ecs.add_entity(world)
    child2 := ecs.add_entity(world)

    ecs.add_pair(world, child1, TestRelation, parent)
    ecs.add_pair(world, child2, TestRelation, parent)

    testing.expect(t, ecs.has_pair(world, child1, TestRelation, parent), "child1 should have TestRelation-parent")
    testing.expect(t, ecs.has_pair(world, child2, TestRelation, parent), "child2 should have TestRelation-parent")

    // Query children of parent
    count := 0
    for arch in ecs.query(world, {ecs.pair(TestRelation, parent)}) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 2, "Should find 2 children of parent")
}

@(test)
test_pair_with_data_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    inventory := ecs.add_entity(world)
    player := ecs.add_entity(world)

    // Player contains 50 items in inventory
    ecs.add_pair(world, player, Contains{amount = 50}, inventory)

    contains := ecs.get_pair(world, player, Contains, inventory)
    testing.expect(t, contains != nil, "Should get Contains data")
    testing.expect(t, contains.amount == 50, "Contains amount should be 50")

    // Update the data
    ecs.add_pair(world, player, Contains{amount = 75}, inventory)
    contains = ecs.get_pair(world, player, Contains, inventory)
    testing.expect(t, contains.amount == 75, "Contains amount should be updated to 75")
}

@(test)
test_get_table_pair :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<5 {
        e := ecs.add_entity(world)
        ecs.add_pair(world, e, Contains{amount = i * 10}, Gold)
    }

    for arch in ecs.query(world, {ecs.pair(Contains, Gold)}) {
        contains_table := ecs.get_table_pair(world, arch, Contains, Gold)
        testing.expect(t, len(contains_table) == 5, "Should have 5 Contains entries")

        for c, i in contains_table {
            testing.expect(t, c.amount == i * 10, fmt.tprintf("Contains[%d].amount should be %d", i, i * 10))
        }
    }
}

@(test)
test_get_table_pair_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    gold_pile := ecs.add_entity(world)

    for i in 0..<3 {
        e := ecs.add_entity(world)
        ecs.add_pair(world, e, Contains{amount = (i + 1) * 100}, gold_pile)
    }

    for arch in ecs.query(world, {ecs.pair(Contains, gold_pile)}) {
        contains_table := ecs.get_table_pair_entity(world, arch, Contains, gold_pile)
        testing.expect(t, len(contains_table) == 3, "Should have 3 Contains entries")
    }
}

@(test)
test_not_pair_term_variants :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    gold := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_pair(world, e1, Contains{10}, gold)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    // No pair

    // Query Position but NOT Contains-gold
    count := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.not(ecs.pair(Contains, gold))}) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity without Contains-gold pair")
}

// =============================================================================
// EMPTY QUERY RESULTS
// =============================================================================

@(test)
test_empty_query :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Query with no entities
    result := ecs.query_raw(world, {ecs.all(Position)})
    testing.expect(t, len(result) == 0, "Empty world should return empty query")

    // Add entity with different component
    e := ecs.add_entity(world)
    ecs.add_component(world, e, Velocity{1, 1})

    result2 := ecs.query_raw(world, {ecs.all(Position)})
    testing.expect(t, len(result2) == 0, "Query for Position should return empty when only Velocity exists")
}

@(test)
test_query_no_terms :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 1})

    // Query with no terms should return nil
    result := ecs.query_raw(world, {})
    testing.expect(t, result == nil, "Query with no terms should return nil")
}

// =============================================================================
// COMPONENT REGISTRATION
// =============================================================================

@(test)
test_explicit_registration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Explicitly register before use
    pos_id := ecs.register_component(world, Position)
    vel_id := ecs.register_component(world, Velocity)

    testing.expect(t, pos_id != vel_id, "Different components should have different IDs")

    // Re-registering should return same ID
    pos_id2 := ecs.register_component(world, Position)
    testing.expect(t, pos_id == pos_id2, "Re-registering should return same ID")

    // get_component_id should work
    retrieved_id, ok := ecs.get_component_id(world, Position)
    testing.expect(t, ok, "get_component_id should succeed")
    testing.expect(t, retrieved_id == pos_id, "Retrieved ID should match registered ID")
}

@(test)
test_auto_registration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Component not registered yet
    _, ok := ecs.get_component_id(world, Position)
    testing.expect(t, !ok, "Position should not be registered yet")

    // Add component (auto-registers)
    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Now should be registered
    _, ok = ecs.get_component_id(world, Position)
    testing.expect(t, ok, "Position should be registered after add_component")
}

// =============================================================================
// ARCHETYPE CLEANUP
// =============================================================================

@(test)
test_archetype_cleanup_on_entity_destroy :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 1})
    ecs.add_component(world, e, Velocity{2, 2})

    // Get archetype count before destroy
    initial_count := len(world.archetypes)

    // Destroy entity (should cleanup empty archetype)
    ecs.remove_entity(world, e)

    // Archetype count should decrease (empty archetypes are cleaned up)
    // Note: empty_archetype is never cleaned up
    final_count := len(world.archetypes)
    testing.expect(t, final_count < initial_count, "Empty archetypes should be cleaned up")
}

@(test)
test_archetype_preserved_with_remaining_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})

    arch := ecs.get_entity_archetype(world, e1)
    testing.expect(t, len(ecs.get_entities(arch)) == 2, "Archetype should have 2 entities")

    // Destroy one entity
    ecs.remove_entity(world, e1)

    // Archetype should still exist with 1 entity
    arch2 := ecs.get_entity_archetype(world, e2)
    testing.expect(t, arch2 != nil, "Archetype should still exist")
    testing.expect(t, len(ecs.get_entities(arch2)) == 1, "Archetype should have 1 entity")
}

// =============================================================================
// SWAP-REMOVE VERIFICATION
// =============================================================================

@(test)
test_swap_remove_preserves_data :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create 5 entities in same archetype
    entities: [5]ecs.EntityID
    for i in 0..<5 {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i * 10)})
    }

    // Delete entity at index 1 (should swap with last)
    ecs.remove_entity(world, entities[1])

    // Verify remaining entities have correct data
    for i in 0..<5 {
        if i == 1 do continue  // Skip deleted

        pos := ecs.get_component(world, entities[i], Position)
        testing.expect(t, pos != nil, fmt.tprintf("Entity %d should still exist", i))
        testing.expect(t, pos.x == f32(i), fmt.tprintf("Entity %d Position.x should be %d", i, i))
        testing.expect(t, pos.y == f32(i * 10), fmt.tprintf("Entity %d Position.y should be %d", i, i * 10))
    }
}

@(test)
test_swap_remove_middle_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create entities
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 10})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 20})

    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Position{3, 30})

    // Delete middle entity
    ecs.remove_entity(world, e2)

    // e1 should be at row 0, e3 should now be at row 1 (swapped from row 2)
    testing.expect(t, ecs.get_entity_row(world, e1) == 0, "e1 should be at row 0")
    testing.expect(t, ecs.get_entity_row(world, e3) == 1, "e3 should be at row 1 after swap")

    // Data should be preserved
    pos1 := ecs.get_component(world, e1, Position)
    pos3 := ecs.get_component(world, e3, Position)

    testing.expect(t, pos1.x == 1 && pos1.y == 10, "e1 data should be preserved")
    testing.expect(t, pos3.x == 3 && pos3.y == 30, "e3 data should be preserved")
}

// =============================================================================
// ENTITY ID HELPERS
// =============================================================================

@(test)
test_entity_id_encoding :: proc(t: ^testing.T) {
    // Test make_entity_id and extraction
    id := ecs.make_entity_id(12345, 42)

    idx := ecs.entity_index(id)
    gen := ecs.entity_generation(id)

    testing.expect(t, idx == 12345, "Index should be 12345")
    testing.expect(t, gen == 42, "Generation should be 42")
}

@(test)
test_entity_id_max_values :: proc(t: ^testing.T) {
    // Test with large values
    max_idx := u64(1 << 48 - 1)
    max_gen := u16(1 << 16 - 1)

    id := ecs.make_entity_id(max_idx, max_gen)

    idx := ecs.entity_index(id)
    gen := ecs.entity_generation(id)

    testing.expect(t, idx == max_idx, "Max index should be preserved")
    testing.expect(t, gen == max_gen, "Max generation should be preserved")
}

// =============================================================================
// MULTIPLE QUERY TERMS
// =============================================================================

@(test)
test_query_multiple_has_terms :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_component(world, e1, Velocity{1, 1})
    ecs.add_component(world, e1, Health{100})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    ecs.add_component(world, e2, Velocity{2, 2})
    // No Health

    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Position{3, 3})
    // No Velocity, No Health

    // Query all three
    count := 0
    for arch in ecs.query(world, {
        ecs.all(Position),
        ecs.all(Velocity),
        ecs.all(Health),
    }) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Only e1 has all three components")
}

@(test)
test_query_multiple_not_terms :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    ecs.add_component(world, e2, Dead{})

    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Position{3, 3})
    ecs.add_component(world, e3, Gold{})

    e4 := ecs.add_entity(world)
    ecs.add_component(world, e4, Position{4, 4})
    ecs.add_component(world, e4, Dead{})
    ecs.add_component(world, e4, Gold{})

    // Query Position but NOT Dead and NOT Gold
    count := 0
    for arch in ecs.query(world, {
        ecs.all(Position),
        ecs.not(ecs.all(Dead)),
        ecs.not(ecs.all(Gold)),
    }) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Only e1 has Position without Dead or Gold")
}

// =============================================================================
// BATCH OPERATIONS EDGE CASES
// =============================================================================

@(test)
test_add_components_with_existing :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Batch add with one existing (Position) and one new (Velocity)
    ecs.add_components(world, e, Position{10, 20}, Velocity{3, 4})

    pos := ecs.get_component(world, e, Position)
    vel := ecs.get_component(world, e, Velocity)

    testing.expect(t, pos.x == 10 && pos.y == 20, "Position should be updated")
    testing.expect(t, vel.x == 3 && vel.y == 4, "Velocity should be added")
}

@(test)
test_add_components_all_existing :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})
    ecs.add_component(world, e, Velocity{3, 4})

    arch_before := ecs.get_entity_archetype(world, e)

    // Batch update existing components (should not change archetype)
    ecs.add_components(world, e, Position{10, 20}, Velocity{30, 40})

    arch_after := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch_before == arch_after, "Archetype should not change when updating existing components")

    pos := ecs.get_component(world, e, Position)
    vel := ecs.get_component(world, e, Velocity)

    testing.expect(t, pos.x == 10 && pos.y == 20, "Position should be updated")
    testing.expect(t, vel.x == 30 && vel.y == 40, "Velocity should be updated")
}

// =============================================================================
// COMPONENT MODIFICATION DURING ITERATION
// =============================================================================

@(test)
test_modify_component_during_iteration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<10 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0})
    }

    // Modify components during iteration (safe - same archetype)
    for arch in ecs.query(world, {ecs.all(Position)}) {
        positions := ecs.get_table(world, arch, Position)
        for &pos in positions {
            pos.y = pos.x * 2
        }
    }

    // Verify modifications
    for arch in ecs.query(world, {ecs.all(Position)}) {
        positions := ecs.get_table(world, arch, Position)
        for pos, i in positions {
            testing.expect(t, pos.y == f32(i) * 2, fmt.tprintf("Position[%d].y should be %f", i, f32(i) * 2))
        }
    }
}

// =============================================================================
// DISTINCT TYPE COMPONENTS
// =============================================================================

@(test)
test_distinct_int_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    Score :: distinct int
    Level :: distinct int

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Score(100))
    ecs.add_component(world, e, Level(5))

    // Should be separate components
    testing.expect(t, ecs.has_component(world, e, Score), "Should have Score")
    testing.expect(t, ecs.has_component(world, e, Level), "Should have Level")

    score := ecs.get_component(world, e, Score)
    level := ecs.get_component(world, e, Level)

    testing.expect(t, score^ == Score(100), "Score should be 100")
    testing.expect(t, level^ == Level(5), "Level should be 5")
}

// =============================================================================
// PAIR ID UTILITIES
// =============================================================================

@(test)
test_pair_id_functions :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Register components to get consistent IDs
    ecs.register_component(world, Contains)
    ecs.register_component(world, Gold)

    pair_id := ecs.get_pair_id(world, Contains, Gold)

    testing.expect(t, ecs.is_pair(pair_id), "Pair ID should be marked as pair")

    rel := ecs.pair_relation(pair_id)
    tgt := ecs.pair_target(pair_id)

    testing.expect(t, rel != 0, "Relation should not be zero")
    testing.expect(t, tgt != 0, "Target should not be zero")
}

// =============================================================================
// PAIR ID ENTITY VARIANTS
// =============================================================================

@(test)
test_get_pair_id_relation_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    target := ecs.add_entity(world)

    // Get pair ID with type relation and entity target
    pair_id := ecs.get_pair_id_relation_entity(world, Contains, target)

    testing.expect(t, ecs.is_pair(pair_id), "Should be marked as pair")
    testing.expect(t, ecs.pair_relation(pair_id) != 0, "Relation should not be zero")
    testing.expect(t, ecs.pair_target(pair_id) != 0, "Target should not be zero")
}

@(test)
test_get_pair_id_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    relation := ecs.add_entity(world)

    // Get pair ID with entity relation and type target
    pair_id := ecs.get_pair_id_entity_target(world, relation, Gold)

    testing.expect(t, ecs.is_pair(pair_id), "Should be marked as pair")
    testing.expect(t, ecs.pair_relation(pair_id) != 0, "Relation should not be zero")
    testing.expect(t, ecs.pair_target(pair_id) != 0, "Target should not be zero")
}

@(test)
test_get_pair_id_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    relation := ecs.add_entity(world)
    target := ecs.add_entity(world)

    // Get pair ID with both entity relation and entity target
    pair_id := ecs.get_pair_id_entities(world, relation, target)

    testing.expect(t, ecs.is_pair(pair_id), "Should be marked as pair")
}

// =============================================================================
// PAIR OPERATION ENTITY VARIANTS
// =============================================================================

@(test)
test_add_pair_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Entity as relation, type as target
    likes_relation := ecs.add_entity(world)
    player := ecs.add_entity(world)

    // Player "likes" Gold (entity relation, type target)
    // Use explicit proc due to ambiguity with data_type when 3rd arg is EntityID
    ecs.add_pair_entity_type(world, player, likes_relation, Gold)

    testing.expect(t, ecs.has_pair(world, player, likes_relation, Gold), "Should have entity-type pair")

    // Remove it
    ecs.remove_pair(world, player, likes_relation, Gold)
    testing.expect(t, !ecs.has_pair(world, player, likes_relation, Gold), "Should not have pair after remove")
}

@(test)
test_remove_pair_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    relation := ecs.add_entity(world)
    target := ecs.add_entity(world)
    subject := ecs.add_entity(world)

    // Add entity-entity pair
    ecs.add_pair(world, subject, relation, target)
    testing.expect(t, ecs.has_pair(world, subject, relation, target), "Should have entity-entity pair")

    // Remove entity-entity pair
    ecs.remove_pair(world, subject, relation, target)
    testing.expect(t, !ecs.has_pair(world, subject, relation, target), "Should not have pair after remove")
}

// =============================================================================
// QUERY TERM ENTITY VARIANTS
// =============================================================================

@(test)
test_has_pair_term_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    likes_relation := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_pair_entity_type(world, e1, likes_relation, Gold)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    // No pair

    // Query with entity relation and type target
    count := 0
    for arch in ecs.query(world, {ecs.pair(likes_relation, Gold)}) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity with (likes_relation, Gold) pair")
}

@(test)
test_has_pair_term_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    relation := ecs.add_entity(world)
    target := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_pair(world, e1, relation, target)

    e2 := ecs.add_entity(world)
    // No pair

    // Query with entity-entity pair
    count := 0
    for arch in ecs.query(world, {ecs.pair(relation, target)}) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity with entity-entity pair")
}

@(test)
test_not_pair_term_relation_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    target := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_pair(world, e1, Contains{10}, target)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    // No pair

    // Query Position but NOT (Contains, target)
    count := 0
    for arch in ecs.query(world, {
        ecs.all(Position),
        ecs.not(ecs.pair(Contains, target)),
    }) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity without (Contains, target) pair")
}

@(test)
test_not_pair_term_entity_target :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    likes_relation := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_pair_entity_type(world, e1, likes_relation, Gold)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    // No pair

    // Query Position but NOT (likes_relation, Gold)
    count := 0
    for arch in ecs.query(world, {
        ecs.all(Position),
        ecs.not(ecs.pair(likes_relation, Gold)),
    }) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity without (likes_relation, Gold) pair")
}

@(test)
test_not_pair_term_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    relation := ecs.add_entity(world)
    target := ecs.add_entity(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_pair_entities(world, e1, relation, target)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{2, 2})
    // No pair

    // Query Position but NOT entity-entity pair
    count := 0
    for arch in ecs.query(world, {
        ecs.all(Position),
        ecs.not(ecs.pair(relation, target)),
    }) {
        count += len(ecs.get_entities(arch))
    }
    testing.expect(t, count == 1, "Should find 1 entity without entity-entity pair")
}

// =============================================================================
// DISABLED COMPONENT EDGE CASES
// =============================================================================

@(test)
test_disable_nonexistent_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Disable a component the entity doesn't have (should be no-op)
    ecs.disable_component(world, e, Health)

    // Entity should still be alive and have Position
    testing.expect(t, ecs.entity_alive(world, e), "Entity should still be alive")
    testing.expect(t, ecs.has_component(world, e, Position), "Should still have Position")
    testing.expect(t, !ecs.is_component_disabled(world, e, Health), "Should not report Health as disabled")
}

@(test)
test_enable_nonexistent_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Enable a component the entity doesn't have (should be no-op)
    ecs.enable_component(world, e, Health)

    // Entity should still be alive and have Position
    testing.expect(t, ecs.entity_alive(world, e), "Entity should still be alive")
    testing.expect(t, ecs.has_component(world, e, Position), "Should still have Position")
}

@(test)
test_disabled_component_still_in_query :: proc(t: ^testing.T) {
    // Note: Current implementation does NOT exclude disabled components from queries
    // This test documents the current behavior
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Health{100})

    // Disable the component
    ecs.disable_component(world, e, Health)
    testing.expect(t, ecs.is_component_disabled(world, e, Health), "Health should be disabled")

    // Query should still find the entity (disabled doesn't filter queries currently)
    count := 0
    for arch in ecs.query(world, {ecs.all(Health)}) {
        count += len(ecs.get_entities(arch))
    }
    // Current behavior: disabled components are NOT filtered from queries
    testing.expect(t, count == 1, "Disabled component entity still appears in query")
}

// =============================================================================
// QUERY EDGE CASES
// =============================================================================

@(test)
test_query_only_not_terms :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Dead{})

    // Query with only NOT terms (should find archetypes without Dead)
    count := 0
    for arch in ecs.query(world, {ecs.not(ecs.all(Dead))}) {
        count += len(ecs.get_entities(arch))
    }
    // Should find e1 (has Position, no Dead) plus the empty archetype potentially
    testing.expect(t, count >= 1, "Should find at least 1 entity without Dead")
}

// =============================================================================
// DISTINCT TYPE DIVERSITY
// =============================================================================

@(test)
test_distinct_f32_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    Temperature :: distinct f32
    Humidity :: distinct f32

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Temperature(98.6))
    ecs.add_component(world, e, Humidity(0.75))

    testing.expect(t, ecs.has_component(world, e, Temperature), "Should have Temperature")
    testing.expect(t, ecs.has_component(world, e, Humidity), "Should have Humidity")

    temp := ecs.get_component(world, e, Temperature)
    hum := ecs.get_component(world, e, Humidity)

    testing.expect(t, temp^ == Temperature(98.6), "Temperature should be 98.6")
    testing.expect(t, hum^ == Humidity(0.75), "Humidity should be 0.75")
}

@(test)
test_distinct_bool_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    IsActive :: distinct bool
    IsVisible :: distinct bool

    e := ecs.add_entity(world)
    ecs.add_component(world, e, IsActive(true))
    ecs.add_component(world, e, IsVisible(false))

    testing.expect(t, ecs.has_component(world, e, IsActive), "Should have IsActive")
    testing.expect(t, ecs.has_component(world, e, IsVisible), "Should have IsVisible")

    active := ecs.get_component(world, e, IsActive)
    visible := ecs.get_component(world, e, IsVisible)

    testing.expect(t, bool(active^) == true, "IsActive should be true")
    testing.expect(t, bool(visible^) == false, "IsVisible should be false")
}

@(test)
test_distinct_u64_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    NetworkID :: distinct u64
    AssetHash :: distinct u64

    e := ecs.add_entity(world)
    ecs.add_component(world, e, NetworkID(0xDEADBEEF))
    ecs.add_component(world, e, AssetHash(0xCAFEBABE))

    testing.expect(t, ecs.has_component(world, e, NetworkID), "Should have NetworkID")
    testing.expect(t, ecs.has_component(world, e, AssetHash), "Should have AssetHash")

    net := ecs.get_component(world, e, NetworkID)
    asset := ecs.get_component(world, e, AssetHash)

    testing.expect(t, net^ == NetworkID(0xDEADBEEF), "NetworkID should be 0xDEADBEEF")
    testing.expect(t, asset^ == AssetHash(0xCAFEBABE), "AssetHash should be 0xCAFEBABE")
}

// =============================================================================
// ENTITY RECYCLING EDGE CASES
// =============================================================================

@(test)
test_entity_recycling_many_cycles :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create and destroy the same slot many times
    first_entity := ecs.add_entity(world)
    first_index := ecs.entity_index(first_entity)
    ecs.remove_entity(world, first_entity)

    // Recycle 100 times
    for i in 0..<100 {
        e := ecs.add_entity(world)
        testing.expect(t, ecs.entity_index(e) == first_index, "Should recycle same index")
        testing.expect(t, ecs.entity_generation(e) == u16(i + 1), fmt.tprintf("Generation should be %d", i + 1))

        // Old entity should still be invalid
        testing.expect(t, !ecs.entity_alive(world, first_entity), "First entity should stay dead")

        ecs.remove_entity(world, e)
    }
}

// =============================================================================
// LARGER SCALE STRESS TEST
// =============================================================================

@(test)
test_many_entities_10k :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    N :: 10000
    entities := make([dynamic]ecs.EntityID, context.temp_allocator)

    // Create entities with varied component combinations
    for i in 0..<N {
        e := ecs.add_entity(world)
        append(&entities, e)

        ecs.add_component(world, e, Position{f32(i), f32(i * 2)})

        if i % 2 == 0 {
            ecs.add_component(world, e, Velocity{1, 1})
        }
        if i % 3 == 0 {
            ecs.add_component(world, e, Health{100})
        }
        if i % 5 == 0 {
            ecs.add_component(world, e, Dead{})
        }
    }

    // Query Position
    count_pos := 0
    for arch in ecs.query(world, {ecs.all(Position)}) {
        count_pos += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_pos == N, fmt.tprintf("Should have %d entities with Position", N))

    // Query Position + Velocity (every 2nd entity)
    count_vel := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.all(Velocity)}) {
        count_vel += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_vel == N / 2, fmt.tprintf("Should have %d entities with Position+Velocity", N / 2))

    // Query Position + Health (every 3rd entity)
    count_health := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.all(Health)}) {
        count_health += len(ecs.get_entities(arch))
    }
    expected_health := N / 3 + (1 if N % 3 > 0 else 0)
    testing.expect(t, count_health == expected_health, fmt.tprintf("Should have ~%d entities with Position+Health", expected_health))

    // Query Position but NOT Dead
    count_alive := 0
    for arch in ecs.query(world, {ecs.all(Position), ecs.not(ecs.all(Dead))}) {
        count_alive += len(ecs.get_entities(arch))
    }
    expected_alive := N - (N / 5 + (1 if N % 5 > 0 else 0))
    testing.expect(t, count_alive == expected_alive, fmt.tprintf("Should have ~%d entities without Dead", expected_alive))

    // Delete every other entity
    for i := 0; i < N; i += 2 {
        ecs.remove_entity(world, entities[i])
    }

    count_remaining := 0
    for arch in ecs.query(world, {ecs.all(Position)}) {
        count_remaining += len(ecs.get_entities(arch))
    }
    testing.expect(t, count_remaining == N / 2, fmt.tprintf("Should have %d entities remaining", N / 2))
}

// =============================================================================
// MAKE_PAIR_ID DIRECT TEST
// =============================================================================

@(test)
test_make_pair_id :: proc(t: ^testing.T) {
    // Test the low-level pair ID construction
    relation := ecs.ComponentID(10)
    target := ecs.ComponentID(20)

    pair_id := ecs.make_pair_id(relation, target)

    testing.expect(t, ecs.is_pair(pair_id), "Should be marked as pair")
    testing.expect(t, ecs.pair_relation(pair_id) == relation, "Relation should be extractable")
    testing.expect(t, ecs.pair_target(pair_id) == target, "Target should be extractable")
}

@(test)
test_pair_id_uniqueness :: proc(t: ^testing.T) {
    // Different pairs should have different IDs
    world := ecs.create_world()
    defer ecs.delete_world(world)

    pair1 := ecs.get_pair_id(world, Contains, Gold)
    pair2 := ecs.get_pair_id(world, Contains, Dead)
    pair3 := ecs.get_pair_id(world, Health, Gold)

    testing.expect(t, pair1 != pair2, "Different targets should produce different pair IDs")
    testing.expect(t, pair1 != pair3, "Different relations should produce different pair IDs")
    testing.expect(t, pair2 != pair3, "Completely different pairs should have different IDs")
}

// =============================================================================
// COMPONENT INFO ACCESS
// =============================================================================

@(test)
test_component_info_size :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Register components
    ecs.register_component(world, Position)
    ecs.register_component(world, Dead)  // Zero-size tag

    pos_id, pos_ok := ecs.get_component_id(world, Position)
    dead_id, dead_ok := ecs.get_component_id(world, Dead)

    testing.expect(t, pos_ok, "Position should be registered")
    testing.expect(t, dead_ok, "Dead should be registered")

    pos_info := world.component_info[pos_id]
    dead_info := world.component_info[dead_id]

    testing.expect(t, pos_info.size == size_of(Position), "Position size should match")
    testing.expect(t, dead_info.size == 0, "Dead (tag) should have size 0")
}

// =============================================================================
// ADD_PAIR_TYPES (NO DATA VARIANT)
// =============================================================================

@(test)
test_add_pair_types_no_data :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Tag-like pair relationship (no data)
    IsA :: distinct struct {}
    Enemy :: distinct struct {}

    e := ecs.add_entity(world)
    ecs.add_pair(world, e, IsA, Enemy)

    testing.expect(t, ecs.has_pair(world, e, IsA, Enemy), "Should have IsA-Enemy pair")

    ecs.remove_pair(world, e, IsA, Enemy)
    testing.expect(t, !ecs.has_pair(world, e, IsA, Enemy), "Should not have pair after remove")
}

@(test)
test_add_entity_with_pair :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    ChildOf :: struct {}
    parent := ecs.add_entity(world)

    // Create entity with pair in one call
    child := ecs.add_entity(world, ecs.pair(ChildOf, parent))

    testing.expect(t, ecs.has_pair(world, child, ChildOf, parent), "Child should have ChildOf pair to parent")
}

@(test)
test_add_entity_with_components_and_pair :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    ChildOf :: struct {}
    parent := ecs.add_entity(world)

    // Create entity with regular components AND a pair
    child := ecs.add_entity(world, Position{10, 20}, ecs.pair(ChildOf, parent))

    testing.expect(t, ecs.has_component(world, child, Position), "Child should have Position")
    pos := ecs.get_component(world, child, Position)
    testing.expect(t, pos.x == 10 && pos.y == 20, "Position should be (10, 20)")
    testing.expect(t, ecs.has_pair(world, child, ChildOf, parent), "Child should have ChildOf pair to parent")
}

// =============================================================================
// DEFERRED OPERATIONS TESTS
// =============================================================================

@(test)
test_deferred_add_during_iteration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create entities
    for i in 0..<5 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i)})
    }

    // During iteration with query_iter, add new component - should be deferred
    count := 0
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for {
        entity, _, _, ok := ecs.query_next(&iter)
        if !ok do break

        // Add Velocity during iteration
        ecs.add_component(world, entity, Velocity{1, 1})
        count += 1

        // has_component should return false (snapshot semantics - deferred not visible)
        testing.expect(t, !ecs.has_component(world, entity, Velocity),
            "has_component should return false for deferred add (snapshot semantics)")
    }
    testing.expect(t, count == 5, "Should have iterated 5 entities")

    // After iteration ends (iterator auto-flushes), components should be applied
    vel_count := 0
    for arch in ecs.query(world, {ecs.all(Velocity)}) {
        vel_count += len(ecs.get_entities(arch))
    }
    testing.expect(t, vel_count == 5, "All 5 entities should have Velocity after flush")
}

@(test)
test_deferred_remove_during_iteration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create entities with Position and Velocity
    for i in 0..<5 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i)})
        ecs.add_component(world, e, Velocity{1, 1})
    }

    // During iteration with query_iter, remove Velocity - should be deferred
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for {
        entity, _, _, ok := ecs.query_next(&iter)
        if !ok do break

        ecs.remove_component(world, entity, Velocity)

        // has_component should return true (snapshot semantics - removal not visible until flush)
        testing.expect(t, ecs.has_component(world, entity, Velocity),
            "has_component should return true for deferred remove (snapshot semantics)")
    }

    // After flush, Velocity should be gone
    vel_count := 0
    for arch in ecs.query(world, {ecs.all(Velocity)}) {
        vel_count += len(ecs.get_entities(arch))
    }
    testing.expect(t, vel_count == 0, "No entities should have Velocity after flush")
}

@(test)
test_deferred_destroy_during_iteration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    entities: [5]ecs.EntityID
    for i in 0..<5 {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i)})
    }

    // Destroy every other entity during iteration with query_iter
    idx := 0
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for {
        entity, _, _, ok := ecs.query_next(&iter)
        if !ok do break

        if idx % 2 == 0 {
            ecs.remove_entity(world, entity)

            // entity_alive should return true (snapshot semantics - destroy not visible until flush)
            testing.expect(t, ecs.entity_alive(world, entity),
                "entity_alive should return true for deferred destroy (snapshot semantics)")
        }
        idx += 1
    }

    // After flush, only half should remain
    remaining := 0
    for arch in ecs.query(world, {ecs.all(Position)}) {
        remaining += len(ecs.get_entities(arch))
    }
    testing.expect(t, remaining == 2, "Only 2 entities should remain (indices 1, 3)")
}

@(test)
test_explicit_flush :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Start iteration
    _ = ecs.query(world, {ecs.all(Position)})
    // Add component (deferred)
    ecs.add_component(world, e, Velocity{3, 4})

    // Explicit flush without starting new query
    ecs.flush(world)

    // Now should be able to get Velocity directly from archetype
    arch := ecs.get_entity_archetype(world, e)
    testing.expect(t, arch != nil, "Entity should have archetype")
    testing.expect(t, ecs.has_component(world, e, Velocity), "Should have Velocity after explicit flush")
}

@(test)
test_deferred_pair_operations :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    gold := ecs.add_entity(world)
    player := ecs.add_entity(world)
    ecs.add_component(world, player, Position{0, 0})

    // Start iteration with query_iter
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for {
        entity, _, _, ok := ecs.query_next(&iter)
        if !ok do break

        // Add pair during iteration
        ecs.add_pair(world, entity, Contains{amount = 100}, gold)

        // has_pair should return false (snapshot semantics - deferred not visible)
        testing.expect(t, !ecs.has_pair(world, entity, Contains, gold),
            "has_pair should return false for deferred pair add (snapshot semantics)")
    }

    // After flush, pair should be there
    pair_count := 0
    for arch in ecs.query(world, {ecs.pair(Contains, gold)}) {
        pair_count += len(ecs.get_entities(arch))
    }
    testing.expect(t, pair_count == 1, "Player should have Contains-gold pair")
}

@(test)
test_iterator_auto_flush :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<3 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i)})
    }

    // Use iterator - should auto-flush when exhausted
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for entity, arch, row in ecs.query_next(&iter) {
        ecs.add_component(world, entity, Health{100})
    }

    // Iterator exhausted, should have flushed
    // Check without starting a new query (direct archetype check)
    health_count := 0
    for arch in world.archetypes {
        if ecs.archetype_has(arch, ecs.ensure_component(world, Health)) {
            health_count += len(arch.entities)
        }
    }
    testing.expect(t, health_count == 3, "All entities should have Health after iterator completes")
}

@(test)
test_query_finish_on_early_break :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    for i in 0..<10 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i)})
    }

    // Early break from iterator
    iter := ecs.query_iter(world, {ecs.all(Position)})
    count := 0
    for entity, arch, row in ecs.query_next(&iter) {
        ecs.add_component(world, entity, Dead{})
        count += 1
        if count >= 3 {
            break
        }
    }

    // Manual finish for early break
    ecs.query_finish(&iter)

    // Should have flushed the 3 Dead components
    dead_count := 0
    for arch in world.archetypes {
        if ecs.archetype_has(arch, ecs.ensure_component(world, Dead)) {
            dead_count += len(arch.entities)
        }
    }
    testing.expect(t, dead_count == 3, "3 entities should have Dead after query_finish")
}

@(test)
test_deferred_no_double_apply :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{0, 0})

    // Start iteration
    _ = ecs.query(world, {ecs.all(Position)})
    // Add Health with value 100
    ecs.add_component(world, e, Health{100})

    // Flush
    ecs.flush(world)

    // Add Health again with value 200 (should update, not duplicate)
    q := ecs.query(world, {ecs.all(Position)})
    for _ in q {
        ecs.add_component(world, e, Health{200})
    }
    ecs.flush(world)

    // Check final value
    hp := ecs.get_component(world, e, Health)
    testing.expect(t, hp != nil && hp.value == 200, "Health should be 200 after second add")
}

@(test)
test_get_component_snapshot_during_iteration :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    // Start iteration with query_iter (enters iteration mode)
    iter := ecs.query_iter(world, {ecs.all(Position)})
    entity, _, _, ok := ecs.query_next(&iter)
    testing.expect(t, ok, "Should have one entity")
    testing.expect(t, entity == e, "Should be our entity")

    // During iteration, add Health (deferred)
    ecs.add_component(world, e, Health{100})

    // get_component should return nil (snapshot semantics - deferred not visible)
    hp := ecs.get_component(world, e, Health)
    testing.expect(t, hp == nil, "get_component should return nil for deferred add (snapshot semantics)")

    // has_component should also return false
    testing.expect(t, !ecs.has_component(world, e, Health), "has_component should not see deferred add")

    // Finish iteration (auto-flushes)
    ecs.query_finish(&iter)

    // After flush, component should be accessible
    hp2 := ecs.get_component(world, e, Health)
    testing.expect(t, hp2 != nil, "get_component should return data after flush")
    testing.expect(t, hp2 != nil && hp2.value == 100, "Health value should be 100 after flush")
}

@(test)
test_get_component_snapshot_after_remove :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})
    ecs.add_component(world, e, Health{100})

    // Start iteration with query_iter (enters iteration mode)
    iter := ecs.query_iter(world, {ecs.all(Position)})
    _, _, _, ok := ecs.query_next(&iter)
    testing.expect(t, ok, "Should have one entity")

    // Remove Health during iteration (deferred)
    ecs.remove_component(world, e, Health)

    // get_component should still return data (snapshot semantics - remove not visible)
    hp := ecs.get_component(world, e, Health)
    testing.expect(t, hp != nil, "get_component should still return data for deferred remove (snapshot semantics)")
    testing.expect(t, hp != nil && hp.value == 100, "Health value should still be 100")

    // has_component should also return true
    testing.expect(t, ecs.has_component(world, e, Health), "has_component should still see component (snapshot semantics)")

    // Finish iteration (auto-flushes)
    ecs.query_finish(&iter)

    // After flush, component is removed
    hp2 := ecs.get_component(world, e, Health)
    testing.expect(t, hp2 == nil, "Health should be removed after flush")
}

// =============================================================================
// OBSERVER TESTS
// =============================================================================

@(test)
test_observer_on_add_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0
    last_entity: ecs.EntityID

    ecs.observe(world, ecs.on_add(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        // Use context to track calls (via raw pointer hack for test)
        ctx := cast(^struct{count: ^int, last: ^ecs.EntityID})context.user_ptr
        ctx.count^ += 1
        ctx.last^ = e
    })

    ctx := struct{count: ^int, last: ^ecs.EntityID}{&count, &last_entity}
    context.user_ptr = &ctx

    e := ecs.add_entity(world)
    testing.expect(t, count == 0, "Observer should not fire yet")

    ecs.add_component(world, e, Position{1, 2})
    testing.expect(t, count == 1, "Observer should fire on add")
    testing.expect(t, last_entity == e, "Observer should receive correct entity")
}

@(test)
test_observer_on_remove_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0
    last_entity: ecs.EntityID

    ecs.observe(world, ecs.on_remove(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^struct{count: ^int, last: ^ecs.EntityID})context.user_ptr
        ctx.count^ += 1
        ctx.last^ = e
    })

    ctx := struct{count: ^int, last: ^ecs.EntityID}{&count, &last_entity}
    context.user_ptr = &ctx

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})
    testing.expect(t, count == 0, "on_remove should not fire on add")

    ecs.remove_component(world, e, Position)
    testing.expect(t, count == 1, "on_remove should fire")
    testing.expect(t, last_entity == e, "Observer should receive correct entity")
}

@(test)
test_observer_on_destroy_entity :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0

    ecs.observe(world, ecs.on_remove(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    ecs.remove_entity(world, e)
    testing.expect(t, count == 1, "on_remove should fire when entity destroyed")
}

@(test)
test_observer_with_filter :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0

    // Only fire when entity has Position but NOT Velocity
    // not() accepts typeid directly
    ecs.observe(world, ecs.on_add(ecs.all(Position), ecs.not(Velocity)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    // Entity with just Position - should fire
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 2})
    testing.expect(t, count == 1, "Should fire for entity with only Position")

    // Entity with Position AND Velocity - should NOT fire
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Velocity{1, 1})
    ecs.add_component(world, e2, Position{3, 4})
    testing.expect(t, count == 1, "Should NOT fire for entity with Velocity")
}

@(test)
test_observer_enter_via_remove :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0

    // Fire when entity has Position but NOT Velocity
    ecs.observe(world, ecs.on_add(ecs.all(Position), ecs.not(Velocity)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    // Create entity with Velocity FIRST, then Position
    e := ecs.add_entity(world)
    ecs.add_component(world, e, Velocity{1, 1})
    ecs.add_component(world, e, Position{1, 2})
    testing.expect(t, count == 0, "Should not fire - has Velocity")

    // Remove Velocity - now entity enters the query
    ecs.remove_component(world, e, Velocity)
    testing.expect(t, count == 1, "Should fire when Velocity removed")
}

@(test)
test_observer_multiple_observers :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count1 := 0
    count2 := 0

    ecs.observe(world, ecs.on_add(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^[2]int)context.user_ptr
        ctx[0] += 1
    })

    ecs.observe(world, ecs.on_add(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^[2]int)context.user_ptr
        ctx[1] += 1
    })

    counts := [2]int{0, 0}
    context.user_ptr = &counts

    e := ecs.add_entity(world)
    ecs.add_component(world, e, Position{1, 2})

    testing.expect(t, counts[0] == 1, "First observer should fire")
    testing.expect(t, counts[1] == 1, "Second observer should fire")
}

@(test)
test_observer_unobserve :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0

    id := ecs.observe(world, ecs.on_add(ecs.all(Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 2})
    testing.expect(t, count == 1, "Observer should fire")

    ecs.unobserve(world, id)

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Position{3, 4})
    testing.expect(t, count == 1, "Observer should not fire after unobserve")
}

@(test)
test_observer_on_entity_create :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0

    // Empty query matches all entities (empty archetype matches empty requirements)
    ecs.observe(world, ecs.on_add(), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    _ = ecs.add_entity(world)
    testing.expect(t, count == 1, "on_add with no terms should fire on entity create")

    _ = ecs.add_entity(world)
    testing.expect(t, count == 2, "Should fire for each entity")
}

@(test)
test_observer_pair :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    count := 0
    TestRelation :: distinct struct {}

    ecs.observe(world, ecs.on_add(ecs.pair(TestRelation, Position)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    e := ecs.add_entity(world)
    ecs.add_pair(world, e, TestRelation, Position)
    testing.expect(t, count == 1, "Observer should fire for pair")
}

@(test)
test_observer_on_pair_remove :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    TestRelation :: distinct struct {}
    Parent :: distinct struct {}
    count := 0

    // When specific (TestRelation, Parent) pair is removed, fire observer
    ecs.observe(world, ecs.on_remove(ecs.pair(TestRelation, Parent)), proc(w: ^ecs.World, e: ecs.EntityID) {
        ctx := cast(^int)context.user_ptr
        ctx^ += 1
    })

    context.user_ptr = &count

    child := ecs.add_entity(world)
    ecs.add_pair(world, child, TestRelation, Parent)

    testing.expect(t, count == 0, "Observer should not fire yet")

    // Explicitly remove the pair
    ecs.remove_pair(world, child, TestRelation, Parent)
    testing.expect(t, count == 1, "Observer should fire when pair removed")
}

// =============================================================================
// TYPE ENTITY TESTS (relation traits)
// =============================================================================

// Relation type for type entity tests
TestRelation :: struct {}

@(test)
test_type_entity_add_and_has :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Add trait to relation type
    ecs.add_component(world, TestRelation, ecs.Exclusive)

    // Verify the trait exists
    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Exclusive), "TestRelation should have Exclusive trait")
    testing.expect(t, !ecs.has_component(world, TestRelation, ecs.Cascade), "TestRelation should not have Cascade trait yet")

    // Add another trait
    ecs.add_component(world, TestRelation, ecs.Cascade)
    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Cascade), "TestRelation should have Cascade trait")
}

@(test)
test_type_entity_get_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Add a component with data to a type
    ecs.add_component(world, TestRelation, Health{value = 100})

    // Get the component
    health := ecs.get_component(world, TestRelation, Health)
    testing.expect(t, health != nil, "Should get Health component from TestRelation type")
    testing.expect(t, health.value == 100, "Health value should be 100")

    // Modify it
    health.value = 200
    health2 := ecs.get_component(world, TestRelation, Health)
    testing.expect(t, health2.value == 200, "Health value should be updated to 200")
}

@(test)
test_type_entity_remove_component :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Add traits
    ecs.add_component(world, TestRelation, ecs.Exclusive)
    ecs.add_component(world, TestRelation, ecs.Cascade)

    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Exclusive), "Should have Exclusive")
    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Cascade), "Should have Cascade")

    // Remove one trait
    ecs.remove_component(world, TestRelation, ecs.Exclusive)

    testing.expect(t, !ecs.has_component(world, TestRelation, ecs.Exclusive), "Should not have Exclusive after removal")
    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Cascade), "Should still have Cascade")
}

@(test)
test_type_entity_independent :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Different types should have independent shadow entities
    OtherRelation :: struct {}

    ecs.add_component(world, TestRelation, ecs.Exclusive)
    ecs.add_component(world, OtherRelation, ecs.Cascade)

    testing.expect(t, ecs.has_component(world, TestRelation, ecs.Exclusive), "TestRelation should have Exclusive")
    testing.expect(t, !ecs.has_component(world, TestRelation, ecs.Cascade), "TestRelation should not have Cascade")
    testing.expect(t, !ecs.has_component(world, OtherRelation, ecs.Exclusive), "OtherRelation should not have Exclusive")
    testing.expect(t, ecs.has_component(world, OtherRelation, ecs.Cascade), "OtherRelation should have Cascade")
}

// =============================================================================
// RELATION TRAIT BEHAVIOR TESTS
// =============================================================================

@(test)
test_exclusive_trait :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    ExclusiveRel :: struct {}
    ecs.add_component(world, ExclusiveRel, ecs.Exclusive)

    target1 := ecs.add_entity(world)
    target2 := ecs.add_entity(world)
    entity := ecs.add_entity(world)

    ecs.add_pair(world, entity, ExclusiveRel, target1)
    testing.expect(t, ecs.has_pair(world, entity, ExclusiveRel, target1), "Should have pair to target1")

    // Adding second target should remove first
    ecs.add_pair(world, entity, ExclusiveRel, target2)
    testing.expect(t, !ecs.has_pair(world, entity, ExclusiveRel, target1), "Should no longer have pair to target1")
    testing.expect(t, ecs.has_pair(world, entity, ExclusiveRel, target2), "Should have pair to target2")
}

@(test)
test_exclusive_trait_multiple_entities :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    ExclusiveRel :: struct {}
    ecs.add_component(world, ExclusiveRel, ecs.Exclusive)

    target1 := ecs.add_entity(world)
    target2 := ecs.add_entity(world)
    entity1 := ecs.add_entity(world)
    entity2 := ecs.add_entity(world)

    // Both entities can have the relation, just only one target each
    ecs.add_pair(world, entity1, ExclusiveRel, target1)
    ecs.add_pair(world, entity2, ExclusiveRel, target2)

    testing.expect(t, ecs.has_pair(world, entity1, ExclusiveRel, target1), "entity1 should have pair to target1")
    testing.expect(t, ecs.has_pair(world, entity2, ExclusiveRel, target2), "entity2 should have pair to target2")

    // Changing entity1's target doesn't affect entity2
    ecs.add_pair(world, entity1, ExclusiveRel, target2)
    testing.expect(t, !ecs.has_pair(world, entity1, ExclusiveRel, target1), "entity1 should no longer have pair to target1")
    testing.expect(t, ecs.has_pair(world, entity1, ExclusiveRel, target2), "entity1 should have pair to target2")
    testing.expect(t, ecs.has_pair(world, entity2, ExclusiveRel, target2), "entity2 should still have pair to target2")
}

@(test)
test_cascade_trait :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    CascadeRel :: struct {}
    ecs.add_component(world, CascadeRel, ecs.Cascade)

    parent := ecs.add_entity(world)
    child1 := ecs.add_entity(world)
    child2 := ecs.add_entity(world)

    ecs.add_pair(world, child1, CascadeRel, parent)
    ecs.add_pair(world, child2, CascadeRel, parent)

    testing.expect(t, ecs.entity_alive(world, child1), "child1 should be alive")
    testing.expect(t, ecs.entity_alive(world, child2), "child2 should be alive")

    // Deleting parent should cascade to children
    ecs.remove_entity(world, parent)

    testing.expect(t, !ecs.entity_alive(world, parent), "parent should be dead")
    testing.expect(t, !ecs.entity_alive(world, child1), "child1 should be dead after cascade")
    testing.expect(t, !ecs.entity_alive(world, child2), "child2 should be dead after cascade")
}

@(test)
test_cascade_recursive :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    CascadeRel :: struct {}
    ecs.add_component(world, CascadeRel, ecs.Cascade)

    grandparent := ecs.add_entity(world)
    parent := ecs.add_entity(world)
    child := ecs.add_entity(world)

    ecs.add_pair(world, parent, CascadeRel, grandparent)
    ecs.add_pair(world, child, CascadeRel, parent)

    // Deleting grandparent should cascade through hierarchy
    ecs.remove_entity(world, grandparent)

    testing.expect(t, !ecs.entity_alive(world, grandparent), "grandparent should be dead")
    testing.expect(t, !ecs.entity_alive(world, parent), "parent should be dead after cascade")
    testing.expect(t, !ecs.entity_alive(world, child), "child should be dead after recursive cascade")
}

@(test)
test_cascade_no_effect_without_trait :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // No Cascade trait on this relation
    NonCascadeRel :: struct {}

    parent := ecs.add_entity(world)
    child := ecs.add_entity(world)

    ecs.add_pair(world, child, NonCascadeRel, parent)

    testing.expect(t, ecs.entity_alive(world, child), "child should be alive")

    // Deleting parent should NOT cascade to children
    ecs.remove_entity(world, parent)

    testing.expect(t, !ecs.entity_alive(world, parent), "parent should be dead")
    testing.expect(t, ecs.entity_alive(world, child), "child should still be alive (no Cascade trait)")
}

@(test)
test_exclusive_no_effect_without_trait :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // No Exclusive trait on this relation
    NonExclusiveRel :: struct {}

    target1 := ecs.add_entity(world)
    target2 := ecs.add_entity(world)
    entity := ecs.add_entity(world)

    ecs.add_pair(world, entity, NonExclusiveRel, target1)
    ecs.add_pair(world, entity, NonExclusiveRel, target2)

    // Both pairs should exist (not exclusive)
    testing.expect(t, ecs.has_pair(world, entity, NonExclusiveRel, target1), "Should have pair to target1")
    testing.expect(t, ecs.has_pair(world, entity, NonExclusiveRel, target2), "Should have pair to target2")
}

// =============================================================================
// MAIN (for running benchmarks manually)
// =============================================================================

main :: proc() {
    fmt.println("Run with: odin test tests/test2.odin -file")
}
