package benchmarks

import ecs "../src"

import "core:fmt"
import "core:time"
import "core:math/rand"

// =============================================================================
// TEST COMPONENTS
// =============================================================================

Position :: struct {
    x, y, z: f32,
}

Velocity :: struct {
    vx, vy, vz: f32,
}

Health :: struct {
    current, max: i32,
}

Damage :: struct {
    amount: i32,
}

Armor :: struct {
    value: i32,
}

Dead :: distinct struct {}
Alive :: distinct struct {}
Player :: distinct struct {}
Enemy :: distinct struct {}

// Relationship types
ChildOf :: distinct struct {}
Owns :: distinct struct {}
Likes :: distinct struct {}

// =============================================================================
// BENCHMARK HARNESS
// =============================================================================

Benchmark :: struct {
    name:       string,
    warmup:     int,
    iterations: int,
}

// Format and print benchmark result with proper spacing
print_result :: proc(name: string, ops_per_sec: f64, elapsed_ms: f64) {
    // Format ops/sec as string to avoid Odin's zero-padding
    ops_str := fmt.tprintf("%d", int(ops_per_sec))

    // Right-pad name to 45 chars
    name_padding := 45 - len(name)
    if name_padding < 1 do name_padding = 1

    // Right-align ops in 12-char field
    ops_padding := 12 - len(ops_str)
    if ops_padding < 0 do ops_padding = 0

    fmt.print(name)
    for _ in 0..<name_padding {
        fmt.print(" ")
    }
    for _ in 0..<ops_padding {
        fmt.print(" ")
    }
    fmt.printf("%s ops/sec  (%8.3f ms)\n", ops_str, elapsed_ms)
}

run_benchmark :: proc(b: Benchmark, setup: proc() -> rawptr, run: proc(state: rawptr, iterations: int), teardown: proc(state: rawptr)) {
    // Setup
    state := setup()

    // Warmup
    for _ in 0..<b.warmup {
        run(state, 1)
    }

    // Timed run
    start := time.now()
    run(state, b.iterations)
    elapsed := time.diff(start, time.now())

    // Teardown
    teardown(state)

    elapsed_ms := time.duration_milliseconds(elapsed)
    ops_per_sec := f64(b.iterations) / time.duration_seconds(elapsed)

    print_result(b.name, ops_per_sec, elapsed_ms)
}

// Simple benchmark that creates fresh world each run
run_simple_benchmark :: proc(name: string, iterations: int, run: proc(world: ^ecs.World, iterations: int)) {
    // Setup
    world := ecs.create_world()

    // Warmup (reduced iterations)
    run(world, iterations / 10)
    ecs.delete_world(world)

    // Fresh world for actual run
    world = ecs.create_world()

    // Timed run
    start := time.now()
    run(world, iterations)
    elapsed := time.diff(start, time.now())

    ecs.delete_world(world)

    elapsed_ms := time.duration_milliseconds(elapsed)
    ops_per_sec := f64(iterations) / time.duration_seconds(elapsed)

    print_result(name, ops_per_sec, elapsed_ms)
}

// =============================================================================
// ENTITY OPERATION BENCHMARKS
// =============================================================================

bench_create_entities :: proc(world: ^ecs.World, n: int) {
    for _ in 0..<n {
        ecs.add_entity(world)
    }
}

bench_destroy_entities :: proc(world: ^ecs.World, n: int) {
    // First create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Now destroy them (this is what we're benchmarking)
    for e in entities {
        ecs.remove_entity(world, e)
    }
}

bench_entity_recycling :: proc(world: ^ecs.World, n: int) {
    // Create/destroy cycle to measure generation bumping
    for _ in 0..<n {
        e := ecs.add_entity(world)
        ecs.remove_entity(world, e)
    }
}

// =============================================================================
// COMPONENT OPERATION BENCHMARKS
// =============================================================================

bench_add_component_single :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Add single component to each
    for i in 0..<n {
        ecs.add_component(world, entities[i], Position{f32(i), f32(i), 0})
    }
}

bench_add_components_batch :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Add 5 components at once using batch API
    for i in 0..<n {
        ecs.add_components(world, entities[i],
            Position{f32(i), f32(i), 0},
            Velocity{1, 0, 0},
            Health{100, 100},
            Damage{10},
            Armor{5},
        )
    }
}

bench_add_components_individual :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Add 5 components individually (for comparison with batch)
    for i in 0..<n {
        ecs.add_component(world, entities[i], Position{f32(i), f32(i), 0})
        ecs.add_component(world, entities[i], Velocity{1, 0, 0})
        ecs.add_component(world, entities[i], Health{100, 100})
        ecs.add_component(world, entities[i], Damage{10})
        ecs.add_component(world, entities[i], Armor{5})
    }
}

bench_remove_component :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities with component
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i), 0})
    }

    // Remove component from each
    for i in 0..<n {
        ecs.remove_component(world, entities[i], Position)
    }
}

bench_get_component :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities with component
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{f32(i), f32(i), 0})
    }

    // Random access lookup
    sum: f32 = 0
    for i in 0..<n {
        idx := rand.int31_max(i32(n))
        pos := ecs.get_component(world, entities[idx], Position)
        if pos != nil {
            sum += pos.x
        }
    }
    // Use sum to prevent optimization
    _ = sum
}

bench_update_component :: proc(world: ^ecs.World, n: int) {
    // Pre-create entities with component
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
        ecs.add_component(world, entities[i], Position{0, 0, 0})
    }

    // Update component data in-place
    for i in 0..<n {
        pos := ecs.get_component(world, entities[i], Position)
        if pos != nil {
            pos.x += 1
            pos.y += 1
        }
    }
}

// =============================================================================
// QUERY PERFORMANCE BENCHMARKS
// =============================================================================

bench_query_simple :: proc(world: ^ecs.World, n: int) {
    // Create entities with Position
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i), 0})
    }

    // Query for Position
    q := ecs.query(world, {ecs.all(Position)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

bench_query_multi :: proc(world: ^ecs.World, n: int) {
    // Create entities with varying components
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})

        if i % 2 == 0 {
            ecs.add_component(world, e, Velocity{1, 0, 0})
        }
        if i % 3 == 0 {
            ecs.add_component(world, e, Health{100, 100})
        }
    }

    // Query with 3 has() terms
    q := ecs.query(world, {ecs.all(Position), ecs.all(Velocity), ecs.all(Health)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

bench_query_with_not :: proc(world: ^ecs.World, n: int) {
    // Create entities, some with Dead tag
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})

        if i % 10 == 0 {
            ecs.add_component(world, e, Dead{})
        }
    }

    // Query with not()
    q := ecs.query(world, {ecs.all(Position), ecs.not(Dead)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

bench_query_pairs :: proc(world: ^ecs.World, n: int) {
    // Create parent entities
    parents := make([]ecs.EntityID, 100)
    defer delete(parents)

    for i in 0..<100 {
        parents[i] = ecs.add_entity(world)
    }

    // Create child entities with ChildOf relationship
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
        parent_idx := i % 100
        ecs.add_pair(world, e, ChildOf, parents[parent_idx])
    }

    // Query with pair wildcard
    q := ecs.query(world, {ecs.pair(ChildOf, ecs.Wildcard)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

bench_query_any_of :: proc(world: ^ecs.World, n: int) {
    // Create entities with different components
    for i in 0..<n {
        e := ecs.add_entity(world)

        if i % 3 == 0 {
            ecs.add_component(world, e, Position{f32(i), 0, 0})
        } else if i % 3 == 1 {
            ecs.add_component(world, e, Velocity{1, 0, 0})
        } else {
            ecs.add_component(world, e, Health{100, 100})
        }
    }

    // Query with any_of
    q := ecs.query(world, {ecs.or(ecs.all(Position), ecs.all(Velocity))})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

// =============================================================================
// QUERY CACHE BENCHMARKS
// =============================================================================

// Benchmark: run same simple query repeatedly (cache hits)
bench_query_cached_simple :: proc(world: ^ecs.World, n: int) {
    // Setup: create entities once
    for i in 0..<1000 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i), 0})
    }

    // Run same query n times - first is miss, rest are hits
    for _ in 0..<n {
        q := ecs.query(world, {ecs.all(Position)})
        for _ in ecs.archs(&q) {}  // Exhaust iterator to clean up
    }
}

// Benchmark: run same wildcard pair query repeatedly (cache hits)
bench_query_cached_wildcard :: proc(world: ^ecs.World, n: int) {
    // Setup: create parent entities
    parents := make([]ecs.EntityID, 100)
    defer delete(parents)

    for i in 0..<100 {
        parents[i] = ecs.add_entity(world)
    }

    // Create child entities with ChildOf relationship
    for i in 0..<1000 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
        parent_idx := i % 100
        ecs.add_pair(world, e, ChildOf, parents[parent_idx])
    }

    // Run same wildcard query n times - first is miss, rest are hits
    for _ in 0..<n {
        q := ecs.query(world, {ecs.pair(ChildOf, ecs.Wildcard)})
        for _ in ecs.archs(&q) {}  // Exhaust iterator to clean up
    }
}

// =============================================================================
// ITERATION PERFORMANCE BENCHMARKS
// =============================================================================

bench_iterate_1_component :: proc(world: ^ecs.World, n: int) {
    // Create entities with Position
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i), 0})
    }

    // Iterate and access 1 component
    sum: f32 = 0
    iter := ecs.query_iter(world, {ecs.all(Position)})
    for {
        entity, arch, row, ok := ecs.query_next(&iter)
        if !ok do break

        pos := ecs.get_component_from_archetype(world, arch, row, Position)
        if pos != nil {
            sum += pos.x
        }
        _ = entity
    }
    _ = sum
}

bench_iterate_3_components :: proc(world: ^ecs.World, n: int) {
    // Create entities with 3 components
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i), 0})
        ecs.add_component(world, e, Velocity{1, 1, 0})
        ecs.add_component(world, e, Health{100, 100})
    }

    // Iterate and access 3 components
    sum: f32 = 0
    iter := ecs.query_iter(world, {ecs.all(Position), ecs.all(Velocity), ecs.all(Health)})
    for {
        entity, arch, row, ok := ecs.query_next(&iter)
        if !ok do break

        pos := ecs.get_component_from_archetype(world, arch, row, Position)
        vel := ecs.get_component_from_archetype(world, arch, row, Velocity)
        hp := ecs.get_component_from_archetype(world, arch, row, Health)

        if pos != nil && vel != nil && hp != nil {
            sum += pos.x + vel.vx + f32(hp.current)
        }
        _ = entity
    }
    _ = sum
}

bench_iterate_with_table :: proc(world: ^ecs.World, n: int) {
    // Create entities with Position
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), f32(i), 0})
    }

    // Iterate using get_table() for batch access
    sum: f32 = 0
    q := ecs.query(world, {ecs.all(Position)})

    for arch in ecs.archs(&q) {
        positions := ecs.get_table(world, arch, Position)
        for &pos in positions {
            sum += pos.x
        }
    }
    _ = sum
}

bench_move_entities :: proc(world: ^ecs.World, n: int) {
    // Create entities with Position + Velocity
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{0, 0, 0})
        ecs.add_component(world, e, Velocity{1, 1, 1})
    }

    // Movement system using batch table access
    q := ecs.query(world, {ecs.all(Position, Velocity)})
    for arch in ecs.archs(&q) {
        positions := ecs.get_table(world, arch, Position)
        velocities := ecs.get_table(world, arch, Velocity)
        for i in 0..<len(positions) {
            positions[i].x += velocities[i].vx
            positions[i].y += velocities[i].vy
            positions[i].z += velocities[i].vz
        }
    }
}

// Pure iteration benchmark - only times the movement loop, not entity creation
bench_move_entities_pure :: proc(world: ^ecs.World, n: int) {
    // Setup: create 100k entities (not timed by outer harness, but we'll time internally)
    for i in 0..<100_000 {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{0, 0, 0})
        ecs.add_component(world, e, Velocity{1, 1, 1})
    }

    // Pre-cache the query and get archetypes
    q := ecs.query(world, {ecs.all(Position, Velocity)})
    archetypes_cache: [dynamic]^ecs.Archetype
    for arch in ecs.archs(&q) {
        append(&archetypes_cache, arch)
    }
    defer delete(archetypes_cache)

    // Time ONLY the movement loop, run it n times
    start := time.now()
    for _ in 0..<n {
        for arch in archetypes_cache {
            positions := ecs.get_table(world, arch, Position)
            velocities := ecs.get_table(world, arch, Velocity)
            for i in 0..<len(positions) {
                positions[i].x += velocities[i].vx
                positions[i].y += velocities[i].vy
                positions[i].z += velocities[i].vz
            }
        }
    }
    elapsed := time.diff(start, time.now())
    elapsed_ms := time.duration_milliseconds(elapsed)

    fmt.printf("  -> Pure move loop: %.3f ms per frame (100k entities x %d frames)\n", elapsed_ms / f64(n), n)
}

// =============================================================================
// PAIR OPERATION BENCHMARKS
// =============================================================================

bench_add_pair_type_type :: proc(world: ^ecs.World, n: int) {
    // Create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Add pair(ChildOf, Player) style
    for i in 0..<n {
        ecs.add_pair(world, entities[i], ChildOf, Player)
    }
}

bench_add_pair_type_entity :: proc(world: ^ecs.World, n: int) {
    // Create target entities
    targets := make([]ecs.EntityID, 100)
    defer delete(targets)

    for i in 0..<100 {
        targets[i] = ecs.add_entity(world)
    }

    // Create entities
    entities := make([]ecs.EntityID, n)
    defer delete(entities)

    for i in 0..<n {
        entities[i] = ecs.add_entity(world)
    }

    // Add pair(ChildOf, target_entity) style
    for i in 0..<n {
        target_idx := i % 100
        ecs.add_pair(world, entities[i], ChildOf, targets[target_idx])
    }
}

bench_query_pair_wildcard :: proc(world: ^ecs.World, n: int) {
    // Create target entities
    targets := make([]ecs.EntityID, 100)
    defer delete(targets)

    for i in 0..<100 {
        targets[i] = ecs.add_entity(world)
    }

    // Create entities with various relationships
    for i in 0..<n {
        e := ecs.add_entity(world)
        target_idx := i % 100

        if i % 3 == 0 {
            ecs.add_pair(world, e, ChildOf, targets[target_idx])
        } else if i % 3 == 1 {
            ecs.add_pair(world, e, Owns, targets[target_idx])
        } else {
            ecs.add_pair(world, e, Likes, targets[target_idx])
        }
    }

    // Query with wildcard - match any target
    q := ecs.query(world, {ecs.pair(ChildOf, ecs.Wildcard)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

// =============================================================================
// OBSERVER OVERHEAD BENCHMARKS
// =============================================================================

// Global counter for observer callbacks
observer_counter: int = 0

observer_callback :: proc(world: ^ecs.World, entity: ecs.EntityID) {
    observer_counter += 1
}

bench_add_with_0_observers :: proc(world: ^ecs.World, n: int) {
    // No observers registered

    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
    }
}

bench_add_with_1_observer :: proc(world: ^ecs.World, n: int) {
    // Register 1 observer
    observer_counter = 0
    obs := ecs.observe(world, ecs.on_add(ecs.all(Position)), observer_callback)
    defer ecs.unobserve(world, obs)

    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
    }
}

bench_add_with_10_observers :: proc(world: ^ecs.World, n: int) {
    // Register 10 observers
    observer_counter = 0
    observers := make([]ecs.ObserverID, 10)
    defer delete(observers)

    for i in 0..<10 {
        observers[i] = ecs.observe(world, ecs.on_add(ecs.all(Position)), observer_callback)
    }

    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
    }

    // Cleanup
    for obs in observers {
        ecs.unobserve(world, obs)
    }
}

bench_observer_callback_overhead :: proc(world: ^ecs.World, n: int) {
    // Measure pure callback invocation overhead
    // Create entities with and without observer
    observer_counter = 0
    obs := ecs.observe(world, ecs.on_add(ecs.all(Position)), observer_callback)
    defer ecs.unobserve(world, obs)

    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})
    }
    // Verify callbacks fired
    _ = observer_counter
}

// =============================================================================
// ARCHETYPE STRESS TEST
// =============================================================================

// Additional components for creating unique archetypes
C1 :: distinct struct {}
C2 :: distinct struct {}
C3 :: distinct struct {}
C4 :: distinct struct {}
C5 :: distinct struct {}
C6 :: distinct struct {}
C7 :: distinct struct {}
C8 :: distinct struct {}
C9 :: distinct struct {}
C10 :: distinct struct {}

bench_many_archetypes :: proc(world: ^ecs.World, n: int) {
    // Create entities that result in many unique archetypes
    // Each entity gets a different combination of tag components
    for i in 0..<n {
        e := ecs.add_entity(world)
        ecs.add_component(world, e, Position{f32(i), 0, 0})

        // Use bit pattern to determine which optional components to add
        bits := i % 1024  // 10 bits = 1024 combinations
        if bits & 1 != 0 do ecs.add_component(world, e, C1{})
        if bits & 2 != 0 do ecs.add_component(world, e, C2{})
        if bits & 4 != 0 do ecs.add_component(world, e, C3{})
        if bits & 8 != 0 do ecs.add_component(world, e, C4{})
        if bits & 16 != 0 do ecs.add_component(world, e, C5{})
        if bits & 32 != 0 do ecs.add_component(world, e, C6{})
        if bits & 64 != 0 do ecs.add_component(world, e, C7{})
        if bits & 128 != 0 do ecs.add_component(world, e, C8{})
        if bits & 256 != 0 do ecs.add_component(world, e, C9{})
        if bits & 512 != 0 do ecs.add_component(world, e, C10{})
    }

    // Query should scan all archetypes
    q := ecs.query(world, {ecs.all(Position)})
    count := 0
    for arch in ecs.archs(&q) {
        count += len(ecs.get_entities(arch))
    }
    _ = count
}

// =============================================================================
// MAIN
// =============================================================================

main :: proc() {
    SEPARATOR :: "======================================================================"
    fmt.println(SEPARATOR)
    fmt.println("odecs Benchmarks")
    fmt.println(SEPARATOR)
    fmt.println()

    N :: 100_000  // Default entity count
    N_SMALL :: 10_000  // For more expensive operations

    // Entity Operations
    fmt.println("--- Entity Operations ---")
    run_simple_benchmark("create_entities", N, bench_create_entities)
    run_simple_benchmark("destroy_entities", N, bench_destroy_entities)
    run_simple_benchmark("entity_recycling", N, bench_entity_recycling)
    fmt.println()

    // Component Operations
    fmt.println("--- Component Operations ---")
    run_simple_benchmark("add_component_single", N, bench_add_component_single)
    run_simple_benchmark("add_components_batch (5 components)", N_SMALL, bench_add_components_batch)
    run_simple_benchmark("add_components_individual (5 components)", N_SMALL, bench_add_components_individual)
    run_simple_benchmark("remove_component", N, bench_remove_component)
    run_simple_benchmark("get_component (random access)", N, bench_get_component)
    run_simple_benchmark("update_component (in-place)", N, bench_update_component)
    fmt.println()

    // Query Performance
    fmt.println("--- Query Performance ---")
    run_simple_benchmark("query_simple (1 term)", N, bench_query_simple)
    run_simple_benchmark("query_multi (3 terms)", N, bench_query_multi)
    run_simple_benchmark("query_with_not", N, bench_query_with_not)
    run_simple_benchmark("query_pairs (wildcard)", N, bench_query_pairs)
    run_simple_benchmark("query_any_of", N, bench_query_any_of)
    fmt.println()

    // Query Cache (repeated queries)
    fmt.println("--- Query Cache (repeated queries) ---")
    run_simple_benchmark("query_cached_simple (100K repeats)", N, bench_query_cached_simple)
    run_simple_benchmark("query_cached_wildcard (100K repeats)", N, bench_query_cached_wildcard)
    fmt.println()

    // Iteration Performance
    fmt.println("--- Iteration Performance ---")
    run_simple_benchmark("iterate_1_component", N, bench_iterate_1_component)
    run_simple_benchmark("iterate_3_components", N, bench_iterate_3_components)
    run_simple_benchmark("iterate_with_table (batch)", N, bench_iterate_with_table)
    run_simple_benchmark("move_entities (pos += vel)", N, bench_move_entities)
    run_simple_benchmark("move_entities_pure (iteration only)", 100, bench_move_entities_pure)
    fmt.println()

    // Pair Operations
    fmt.println("--- Pair Operations ---")
    run_simple_benchmark("add_pair (type, type)", N, bench_add_pair_type_type)
    run_simple_benchmark("add_pair (type, entity)", N, bench_add_pair_type_entity)
    run_simple_benchmark("query_pair_wildcard", N, bench_query_pair_wildcard)
    fmt.println()

    // Observer Overhead
    fmt.println("--- Observer Overhead ---")
    run_simple_benchmark("add_with_0_observers", N, bench_add_with_0_observers)
    run_simple_benchmark("add_with_1_observer", N, bench_add_with_1_observer)
    run_simple_benchmark("add_with_10_observers", N, bench_add_with_10_observers)
    fmt.println()

    // Archetype Stress
    fmt.println("--- Archetype Stress ---")
    run_simple_benchmark("many_archetypes (1024 unique)", N_SMALL, bench_many_archetypes)
    fmt.println()

    fmt.println(SEPARATOR)
    fmt.println("Benchmarks complete")
    fmt.println(SEPARATOR)
}
