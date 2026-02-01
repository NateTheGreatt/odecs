package ecs

import "core:mem"
import "core:slice"

// =============================================================================
// ENTITY RECORD
// =============================================================================

Entity_Record :: struct {
    archetype: ^Archetype,
    row:       int,
}

// =============================================================================
// DEFERRED OPERATIONS
// =============================================================================

Deferred_Op :: union {
    Deferred_Add,
    Deferred_Remove,
    Deferred_Destroy,
}

Deferred_Add :: struct {
    entity:       EntityID,
    component_id: ComponentID,
    data:         rawptr,      // nil for tags, allocated copy for data
    data_size:    int,
}

Deferred_Remove :: struct {
    entity:       EntityID,
    component_id: ComponentID,
}

Deferred_Destroy :: struct {
    entity: EntityID,
}

// =============================================================================
// WORLD
// =============================================================================

World :: struct {
    // Component registry
    component_info:      map[ComponentID]Component_Info,
    type_to_component:   map[typeid]ComponentID,
    component_to_type:   map[ComponentID]typeid,  // Reverse lookup for trait checks
    next_component_id:   ComponentID,

    // Entity storage - sparse-dense set for O(1) liveness checks
    entity_index:       Entity_Index,             // Sparse-dense entity ID management
    records:            [dynamic]Entity_Record,   // Archetype/row per entity index

    // Per-entity disabled components (entity -> set of disabled component IDs)
    disabled_components: map[EntityID]map[ComponentID]struct{},

    // Archetype storage - dense array for cache-friendly iteration
    archetypes:         [dynamic]^Archetype,
    archetype_index:    map[ArchetypeID]int,  // ID -> index in archetypes array
    empty_archetype:    ^Archetype,

    // Deferred operations (for safe iteration)
    deferred_ops:       [dynamic]Deferred_Op,
    iteration_depth:    int,
    is_flushing:        bool,  // Prevents recursive flush
    archetypes_to_remove: [dynamic]^Archetype,  // Removed at end of flush
    auto_cleanup_archetypes: bool,  // If true, empty archetypes are removed at end of flush

    // Observers
    observers:          [dynamic]Observer,
    observer_index:     map[ObserverID]int,
    next_observer_id:   ObserverID,

    // Query cache
    query_cache:          map[u64]Cached_Query,
    archetype_generation: u64,

    // Type entities (shadow entities for attaching components to types)
    type_entities:        map[typeid]EntityID,

    // Memory
    allocator:          mem.Allocator,
}

Cached_Query :: struct {
    archetypes:    [dynamic]^Archetype,
    generation:    u64,
    captures:      []Capture_Info,    // Cloned with world.allocator
    required_cids: []ComponentID,     // Cloned with world.allocator
}

create_world :: proc(allocator := context.allocator) -> ^World {
    world := new(World, allocator)
    world.allocator = allocator
    world.component_info = make(map[ComponentID]Component_Info, allocator = allocator)
    world.type_to_component = make(map[typeid]ComponentID, allocator = allocator)
    world.component_to_type = make(map[ComponentID]typeid, allocator = allocator)

    // Initialize sparse-dense entity index
    world.entity_index = Entity_Index{
        dense       = make([dynamic]EntityID, allocator),
        sparse      = make([dynamic]u32, allocator),
        alive_count = 0,
        max_id      = 0,
    }
    world.records = make([dynamic]Entity_Record, allocator)
    world.disabled_components = make(map[EntityID]map[ComponentID]struct{}, allocator = allocator)
    world.archetypes = make([dynamic]^Archetype, allocator)
    world.archetype_index = make(map[ArchetypeID]int, allocator = allocator)
    world.deferred_ops = make([dynamic]Deferred_Op, 0, 256, allocator)  // Pre-allocate to avoid reallocations during flush
    world.next_component_id = FIRST_ENTITY_INDEX
    world.iteration_depth = 0
    world.archetypes_to_remove = make([dynamic]^Archetype, allocator)
    world.observers = make([dynamic]Observer, allocator)
    world.observer_index = make(map[ObserverID]int, allocator = allocator)
    world.next_observer_id = 1
    world.query_cache = make(map[u64]Cached_Query, allocator = allocator)
    world.archetype_generation = 0
    world.auto_cleanup_archetypes = true
    world.type_entities = make(map[typeid]EntityID, allocator = allocator)

    // Create empty archetype for entities with no components
    empty_type: [0]ComponentID
    world.empty_archetype = get_or_create_archetype(world, empty_type[:])

    return world
}

delete_world :: proc(world: ^World) {
    if world == nil do return

    // Free any pending deferred op data
    for op in world.deferred_ops {
        if add, ok := op.(Deferred_Add); ok {
            if add.data != nil {
                free(add.data, world.allocator)
            }
        }
    }
    delete(world.deferred_ops)
    delete(world.archetypes_to_remove)

    // Free observers
    for &obs in world.observers {
        delete(obs.required, world.allocator)
        delete(obs.excluded, world.allocator)
    }
    delete(world.observers)
    delete(world.observer_index)

    // First pass: free all edge column_maps and clear edge maps
    // This prevents use-after-free when archetype_destroy tries to access
    // edge.target archetypes that were already freed earlier in the loop
    for arch in world.archetypes {
        for _, edge in arch.add_edges {
            delete(edge.column_map, world.allocator)
        }
        for _, edge in arch.remove_edges {
            delete(edge.column_map, world.allocator)
        }
        clear(&arch.add_edges)
        clear(&arch.remove_edges)
    }

    // Second pass: destroy archetypes (edge maps are now empty, no cross-archetype access)
    for arch in world.archetypes {
        archetype_destroy(arch, world)
        free(arch, world.allocator)
    }
    delete(world.archetypes)
    delete(world.archetype_index)
    delete(world.component_info)
    delete(world.type_to_component)
    delete(world.component_to_type)
    delete(world.entity_index.dense)
    delete(world.entity_index.sparse)
    delete(world.records)

    // Free nested disabled component maps
    for _, inner_map in world.disabled_components {
        delete(inner_map)
    }
    delete(world.disabled_components)

    // Free query cache
    for _, &cached in world.query_cache {
        delete(cached.archetypes)
        delete(cached.captures, world.allocator)
        delete(cached.required_cids, world.allocator)
    }
    delete(world.query_cache)

    // Free type entities map
    delete(world.type_entities)

    free(world, world.allocator)
}

// Clear the query cache to free memory (queries will rebuild on next use)
clear_query_cache :: proc(world: ^World) {
    for _, &cached in world.query_cache {
        delete(cached.archetypes)
        delete(cached.captures, world.allocator)
        delete(cached.required_cids, world.allocator)
    }
    clear(&world.query_cache)
}


// =============================================================================
// DEFERRED OPERATION FLUSH
// =============================================================================

// Flush all pending deferred operations (public API)
flush :: proc(world: ^World) {
    flush_deferred(world)
}

// Internal flush implementation
flush_deferred :: proc(world: ^World) {
    if len(world.deferred_ops) == 0 do return
    if world.is_flushing do return  // Prevent recursive flush

    world.is_flushing = true

    // Process all deferred operations using index-based iteration
    // This handles new ops being added during processing (they go to the end)
    i := 0
    for i < len(world.deferred_ops) {
        op := world.deferred_ops[i]
        switch o in op {
        case Deferred_Add:
            add_component_by_id_immediate(world, o.entity, o.component_id, o.data)
            if o.data != nil {
                free(o.data, world.allocator)
            }
        case Deferred_Remove:
            remove_component_by_id_immediate(world, o.entity, o.component_id)
        case Deferred_Destroy:
            remove_entity_immediate(world, o.entity)
        }
        i += 1
    }
    clear(&world.deferred_ops)

    world.is_flushing = false

    // Clean up empty archetypes if enabled
    if world.auto_cleanup_archetypes {
        for arch in world.archetypes_to_remove {
            if len(arch.entities) == 0 && arch != world.empty_archetype {
                remove_archetype(world, arch)
            }
        }
    }
    clear(&world.archetypes_to_remove)
}

// Manually clean up empty archetypes (useful when auto_cleanup_archetypes is false)
cleanup_empty_archetypes :: proc(world: ^World) {
    if is_iterating(world) || world.is_flushing {
        return  // Not safe to remove during iteration/flush
    }

    // Collect empty archetypes (can't remove while iterating the array)
    to_remove := make([dynamic]^Archetype, context.temp_allocator)
    for arch in world.archetypes {
        if len(arch.entities) == 0 && arch != world.empty_archetype {
            append(&to_remove, arch)
        }
    }

    // Remove them
    for arch in to_remove {
        remove_archetype(world, arch)
    }
}

// Check if currently iterating (for internal use)
is_iterating :: proc(world: ^World) -> bool {
    return world.iteration_depth > 0
}

// =============================================================================
// ARCHETYPE LOOKUP & CREATION
// =============================================================================

// Hash a query context for cache lookup (FNV-1a)
hash_query_context :: proc(ctx: ^Query_Context) -> u64 {
    h := u64(0xcbf29ce484222325)

    // Hash required (must sort for consistent hashing)
    req_sorted := slice.clone(ctx.required[:], context.temp_allocator)
    sort_signature(req_sorted)
    for cid in req_sorted {
        h = (h ~ u64(cid)) * 0x100000001b3
    }
    h = (h ~ 0xFF) * 0x100000001b3  // Separator

    // Hash excluded (must sort for consistent hashing)
    exc_sorted := slice.clone(ctx.excluded[:], context.temp_allocator)
    sort_signature(exc_sorted)
    for cid in exc_sorted {
        h = (h ~ u64(cid)) * 0x100000001b3
    }
    h = (h ~ 0xFF) * 0x100000001b3  // Separator

    // Hash wildcard terms
    for wt in ctx.wildcard_terms {
        h = (h ~ u64(wt.relation_cid)) * 0x100000001b3
        h = (h ~ u64(wt.negate ? 1 : 0)) * 0x100000001b3
    }
    h = (h ~ 0xFF) * 0x100000001b3  // Separator

    // Hash any_of groups (hash term count per group as simple discriminator)
    for group in ctx.any_of_groups {
        h = (h ~ u64(len(group.terms))) * 0x100000001b3
    }

    return h
}

get_or_create_archetype :: proc(world: ^World, sig: []ComponentID) -> ^Archetype {
    sorted := slice.clone(sig, context.temp_allocator)
    sort_signature(sorted)

    id := hash_signature(sorted)
    if idx, ok := world.archetype_index[id]; ok {
        return world.archetypes[idx]
    }

    arch := new(Archetype, world.allocator)
    archetype_init(arch, world, sorted)
    world.archetype_index[id] = len(world.archetypes)
    append(&world.archetypes, arch)
    world.archetype_generation += 1  // Invalidate query cache
    return arch
}
