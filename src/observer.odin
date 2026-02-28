package ecs

import "core:slice"

// =============================================================================
// OBSERVERS
// =============================================================================

Observer_Event :: enum { On_Add, On_Remove }

Observer_Def :: struct {
    event: Observer_Event,
    terms: []Term,
}

Observer :: struct {
    id:       ObserverID,
    event:    Observer_Event,
    required: []ComponentID,
    excluded: []ComponentID,
    callback: proc(world: ^World, entity: EntityID),
}

// =============================================================================
// OBSERVER API
// =============================================================================

on_add :: proc(types: ..typeid) -> Observer_Def {
    // Decode typeids to Terms
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    return Observer_Def{
        event = .On_Add,
        terms = terms,
    }
}

on_remove :: proc(types: ..typeid) -> Observer_Def {
    // Decode typeids to Terms
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    return Observer_Def{
        event = .On_Remove,
        terms = terms,
    }
}

observe :: proc(world: ^World, def: Observer_Def, callback: proc(world: ^World, entity: EntityID)) -> ObserverID {
    // Build with temp_allocator (fast), then clone to exact-sized slices (no wasted capacity)
    required := make([dynamic]ComponentID, context.temp_allocator)
    excluded := make([dynamic]ComponentID, context.temp_allocator)
    process_terms(world, def.terms, &required, &excluded)

    id := world.next_observer_id
    world.next_observer_id += 1

    obs := Observer{
        id       = id,
        event    = def.event,
        required = slice.clone(required[:], world.allocator),
        excluded = slice.clone(excluded[:], world.allocator),
        callback = callback,
    }

    world.observer_index[id] = len(world.observers)
    append(&world.observers, obs)
    return id
}

unobserve :: proc(world: ^World, id: ObserverID) {
    idx, ok := world.observer_index[id]
    if !ok do return

    // Free the observer's slices
    obs := &world.observers[idx]
    delete(obs.required, world.allocator)
    delete(obs.excluded, world.allocator)

    // Swap-remove
    last_idx := len(world.observers) - 1
    if idx != last_idx {
        last_obs := world.observers[last_idx]
        world.observers[idx] = last_obs
        world.observer_index[last_obs.id] = idx
    }

    delete_key(&world.observer_index, id)
    pop(&world.observers)
}

// Check if an archetype matches an observer's requirements
observer_matches_archetype :: proc(obs: ^Observer, arch: ^Archetype) -> bool {
    if arch == nil do return false
    for cid in obs.required {
        if !archetype_has(arch, cid) do return false
    }
    for cid in obs.excluded {
        if archetype_has(arch, cid) do return false
    }
    return true
}

// Fire observers for an archetype transition
check_observers :: proc(world: ^World, entity: EntityID, from: ^Archetype, to: ^Archetype) {
    for &obs in world.observers {
        from_matches := observer_matches_archetype(&obs, from)
        to_matches := observer_matches_archetype(&obs, to)

        if obs.event == .On_Add && !from_matches && to_matches {
            obs.callback(world, entity)
        } else if obs.event == .On_Remove && from_matches && !to_matches {
            obs.callback(world, entity)
        }
    }
}
