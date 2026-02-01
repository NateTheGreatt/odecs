package ecs

import "core:mem"

// Queue empty archetype for removal (deduplicates)
queue_archetype_removal :: proc(world: ^World, arch: ^Archetype) {
    if len(arch.entities) != 0 || arch == world.empty_archetype do return
    if world.is_flushing {
        for a in world.archetypes_to_remove {
            if a == arch do return
        }
        append(&world.archetypes_to_remove, arch)
    } else if world.auto_cleanup_archetypes {
        remove_archetype(world, arch)
    }
}

// =============================================================================
// COMPONENT REGISTRATION
// =============================================================================

register_component :: proc(world: ^World, $T: typeid) -> ComponentID {
    if cid, ok := world.type_to_component[T]; ok {
        return cid
    }

    cid := world.next_component_id
    world.next_component_id += 1

    ti := type_info_of(T)
    world.component_info[cid] = Component_Info{
        size      = size_of(T),
        alignment = align_of(T),
        type_info = ti,
    }
    world.type_to_component[T] = cid
    world.component_to_type[cid] = T  // Reverse lookup for O(1) trait checks
    return cid
}

get_component_id :: #force_inline proc(world: ^World, $T: typeid) -> (ComponentID, bool) {
    cid, ok := world.type_to_component[T]
    return cid, ok
}

// Runtime version - takes typeid as a value instead of compile-time parameter
get_component_id_from_typeid :: #force_inline proc(world: ^World, t: typeid) -> (ComponentID, bool) {
    cid, ok := world.type_to_component[t]
    return cid, ok
}

ensure_component :: proc(world: ^World, $T: typeid) -> ComponentID {
    if cid, ok := world.type_to_component[T]; ok {
        return cid
    }
    return register_component(world, T)
}

// =============================================================================
// ENTITY MANAGEMENT
// =============================================================================

// Create a new entity, optionally with initial components
// Usage: add_entity(world) or add_entity(world, Position{0,0}, Velocity{1,1})
add_entity :: proc(world: ^World, components: ..any) -> EntityID {
    ei := &world.entity_index

    // Allocate entity ID using sparse-dense pattern
    entity: EntityID
    idx: u32

    if ei.alive_count < u32(len(ei.dense)) {
        // Recycle from dead zone: dense[alive_count] has a dead entity
        recycled := ei.dense[ei.alive_count]
        idx = u32(entity_index(recycled))
        // Increment generation
        gen := entity_generation(recycled) + 1
        entity = make_entity_id(u64(idx), gen)
        ei.dense[ei.alive_count] = entity
        ei.sparse[idx] = ei.alive_count
    } else {
        // Create new entity
        ei.max_id += 1
        idx = ei.max_id
        entity = make_entity_id(u64(idx), 0)
        append(&ei.dense, entity)
        // Grow sparse array to fit
        for u32(len(ei.sparse)) <= idx {
            append(&ei.sparse, 0)
        }
        ei.sparse[idx] = ei.alive_count
    }
    ei.alive_count += 1

    // Grow records array if needed
    for u32(len(world.records)) <= idx {
        append(&world.records, Entity_Record{})
    }

    // No components - use empty archetype
    if len(components) == 0 {
        record := &world.records[idx]
        record.archetype = world.empty_archetype
        record.row = archetype_add_entity(world.empty_archetype, entity)
        check_observers(world, entity, nil, world.empty_archetype)
        return entity
    }

    // Collect component IDs and data
    cids := make([dynamic]ComponentID, context.temp_allocator)
    component_data := make(map[ComponentID]rawptr, allocator = context.temp_allocator)

    for comp in components {
        // Handle Term (pair) specially
        if comp.id == Term {
            term := (cast(^Term)comp.data)^
            pair_cid, data_size, ok := resolve_term_to_pair(world, term)
            if ok {
                ensure_pair_registered(world, pair_cid, data_size)
                append(&cids, pair_cid)
                // Pairs from Term have no inline data
            }
            continue
        }

        cid := resolve_type(world, comp.id)
        append(&cids, cid)
        component_data[cid] = comp.data
    }

    // Get or create target archetype directly (skip empty archetype)
    target := get_or_create_archetype(world, cids[:])
    row := archetype_add_entity(target, entity)

    // Set component data
    for cid, data in component_data {
        info := world.component_info[cid]
        if info.size > 0 && data != nil {
            col_idx := archetype_get_column(target, cid)
            col := &target.columns[col_idx]
            column_set(col, row, data)
        }
    }

    // Update entity record
    record := &world.records[idx]
    record.archetype = target
    record.row = row

    // Fire observers (nil -> target)
    check_observers(world, entity, nil, target)

    return entity
}

remove_entity :: proc(world: ^World, entity: EntityID) {
    // Defer during iteration OR during flush (observers can fire during flush)
    if is_iterating(world) || world.is_flushing {
        // Defer destruction during iteration
        append(&world.deferred_ops, Deferred_Destroy{entity})
        return
    }
    remove_entity_immediate(world, entity)
}

remove_entity_immediate :: proc(world: ^World, entity: EntityID) {
    if !entity_alive(world, entity) do return

    idx := u32(entity_index(entity))
    record := &world.records[idx]

    // Cascade deletion: delete entities with Cascade pairs targeting this entity
    cascade_delete_dependents(world, entity)

    arch := record.archetype

    // Fire observers before removal (arch -> nil)
    check_observers(world, entity, arch, nil)

    moved, had_move := archetype_remove_entity(arch, record.row)
    if had_move {
        // Update moved entity's record
        moved_idx := u32(entity_index(moved))
        world.records[moved_idx].row = record.row
    }

    queue_archetype_removal(world, arch)

    // Clean up any disabled component tracking for this entity
    if inner, ok := world.disabled_components[entity]; ok {
        delete(inner)
        delete_key(&world.disabled_components, entity)
    }

    // Remove from sparse-dense set using swap-and-pop
    ei := &world.entity_index
    dense_idx := ei.sparse[idx]
    last_idx := ei.alive_count - 1

    if dense_idx != last_idx {
        // Swap with last alive entity
        last_entity := ei.dense[last_idx]
        last_entity_idx := u32(entity_index(last_entity))

        ei.dense[dense_idx] = last_entity
        ei.sparse[last_entity_idx] = dense_idx
    }

    // Move dead entity to the dead zone (keeps its ID for recycling with bumped gen)
    ei.dense[last_idx] = entity
    ei.sparse[idx] = last_idx
    ei.alive_count -= 1

    // Clear record
    record.archetype = nil
    record.row = -1
}

entity_alive :: #force_inline proc(world: ^World, entity: EntityID) -> bool {
    idx := u32(entity_index(entity))
    ei := &world.entity_index
    if idx >= u32(len(ei.sparse)) do return false
    dense_idx := ei.sparse[idx]
    return dense_idx < ei.alive_count && ei.dense[dense_idx] == entity
}


// Get the archetype row for an entity
get_entity_row :: proc(world: ^World, entity: EntityID) -> int {
    if !entity_alive(world, entity) do return -1
    idx := u32(entity_index(entity))
    return world.records[idx].row
}

// Get the archetype for an entity
get_entity_archetype :: proc(world: ^World, entity: EntityID) -> ^Archetype {
    if !entity_alive(world, entity) do return nil
    idx := u32(entity_index(entity))
    return world.records[idx].archetype
}

// =============================================================================
// COMPONENT OPERATIONS
// =============================================================================

// Move entity between archetypes, copying shared component data
move_entity :: proc(world: ^World, entity: EntityID, from: ^Archetype, to: ^Archetype, column_map: []i16) {
    idx := u32(entity_index(entity))
    record := &world.records[idx]
    old_row := record.row

    // Validate old_row is in bounds
    assert(old_row >= 0 && old_row < len(from.entities), "move_entity: old_row out of bounds")
    assert(from.entities[old_row] == entity, "move_entity: entity mismatch at old_row")

    // Add to new archetype
    new_row := archetype_add_entity(to, entity)

    // Copy shared component data using pre-computed column mapping (O(columns), no lookups)
    for to_col := 0; to_col < len(column_map); to_col += 1 {
        from_col := column_map[to_col]
        if from_col >= 0 {
            column_copy_row(&to.columns[to_col], new_row, &from.columns[from_col], old_row)
        } else {
            // Zero-initialize new component
            col := &to.columns[to_col]
            mem.zero(&col.data[new_row * col.elem_size], col.elem_size)
        }
    }

    // Remove from old archetype
    moved, had_move := archetype_remove_entity(from, old_row)
    if had_move {
        moved_idx := u32(entity_index(moved))
        world.records[moved_idx].row = old_row
    }

    // Update record
    record.archetype = to
    record.row = new_row

    // Fire observers
    check_observers(world, entity, from, to)

    queue_archetype_removal(world, from)
}

add_component_entity :: proc(world: ^World, entity: EntityID, component: $T) {
    // Handle Term (pair) specially at compile time
    when T == Term {
        add_component_term_impl(world, entity, component)
    } else {
        add_component_value_impl(world, entity, component)
    }
}

add_component :: proc {
    add_component_entity,
    add_component_to_type,
    add_component_type_to_type,
}

add_component_value_impl :: proc(world: ^World, entity: EntityID, component: $T) {
    if !entity_alive(world, entity) do return

    cid := ensure_component(world, T)

    // Defer during iteration OR during flush (observers can fire during flush)
    if is_iterating(world) || world.is_flushing {
        // Defer the add during iteration
        data_copy: rawptr = nil
        when size_of(T) > 0 {
            err: mem.Allocator_Error
            data_copy, err = mem.alloc(size_of(T), align_of(T), world.allocator)
            if err != nil {
                panic("ECS: Failed to allocate deferred component data")
            }
            local := component
            mem.copy(data_copy, &local, size_of(T))
        }
        append(&world.deferred_ops, Deferred_Add{
            entity       = entity,
            component_id = cid,
            data         = data_copy,
            data_size    = size_of(T),
        })
        return
    }

    add_component_immediate(world, entity, cid, component)
}

// Resolve a Term to a pair ComponentID
// Returns (pair_cid, data_size, ok)
resolve_term_to_pair :: proc(world: ^World, term: Term) -> (ComponentID, int, bool) {
    if term.kind != .Pair {
        return 0, 0, false
    }

    pair_cid: ComponentID
    data_size := 0

    if term.relation != nil {
        // Type relation
        r_cid := resolve_type(world, term.relation)
        ti := type_info_of(term.relation)
        if ti != nil {
            data_size = ti.size
        }

        switch t in term.target {
        case typeid:
            t_cid := resolve_type(world, t)
            pair_cid = make_pair_id(r_cid, t_cid)
        case EntityID:
            t_id := ComponentID(entity_index(t))
            pair_cid = make_pair_id(r_cid, t_id)
        case Wildcard_T, Any_T, Var:
            return 0, 0, false
        }
    } else {
        // Entity relation
        r_id := ComponentID(entity_index(term.relation_entity))

        switch t in term.target {
        case typeid:
            t_cid := resolve_type(world, t)
            pair_cid = make_pair_id(r_id, t_cid)
        case EntityID:
            t_id := ComponentID(entity_index(t))
            pair_cid = make_pair_id(r_id, t_id)
        case Wildcard_T, Any_T, Var:
            return 0, 0, false
        }
    }

    return pair_cid, data_size, true
}

// Add a pair component via Term (from pair() call)
add_component_term_impl :: proc(world: ^World, entity: EntityID, term: Term) {
    assert(term.kind == .Pair, "add_component with Term only supports pair terms")
    if !entity_alive(world, entity) do return

    pair_cid, data_size, ok := resolve_term_to_pair(world, term)
    if !ok {
        assert(false, "Cannot add_component with wildcard/any/var target")
        return
    }

    ensure_pair_registered(world, pair_cid, data_size)
    add_component_by_id(world, entity, pair_cid, nil)
}

add_component_immediate :: proc(world: ^World, entity: EntityID, cid: ComponentID, component: $T) {
    idx := u32(entity_index(entity))
    record := &world.records[idx]
    arch := record.archetype

    // Already has component?
    if archetype_has(arch, cid) {
        // Just update the data
        when size_of(T) > 0 {
            col_idx := archetype_get_column(arch, cid)
            col := &arch.columns[col_idx]
            local := component
            column_set(col, record.row, &local)
        }
        return
    }

    // Find or create target archetype via edge cache
    edge: Archetype_Edge
    if cached, ok := arch.add_edges[cid]; ok {
        edge = cached
    } else {
        // Build new type
        new_type := make([dynamic]ComponentID, context.temp_allocator)
        append(&new_type, ..arch.signature)
        append(&new_type, cid)
        target := get_or_create_archetype(world, new_type[:])
        // Compute column mappings for both directions
        edge = Archetype_Edge{
            target     = target,
            column_map = compute_column_map(arch, target, world.allocator),
        }
        reverse_edge := Archetype_Edge{
            target     = arch,
            column_map = compute_column_map(target, arch, world.allocator),
        }
        arch.add_edges[cid] = edge
        target.remove_edges[cid] = reverse_edge
    }

    move_entity(world, entity, arch, edge.target, edge.column_map)

    // Set the new component data
    when size_of(T) > 0 {
        record = &world.records[idx]  // Re-fetch after move
        col_idx := archetype_get_column(edge.target, cid)
        col := &edge.target.columns[col_idx]
        local := component
        column_set(col, record.row, &local)
    }
}

remove_component_entity :: proc(world: ^World, entity: EntityID, $T: typeid) {
    if !entity_alive(world, entity) do return

    cid, ok := get_component_id(world, T)
    if !ok do return

    // Defer during iteration OR during flush (observers can fire during flush)
    if is_iterating(world) || world.is_flushing {
        // Defer the remove during iteration
        append(&world.deferred_ops, Deferred_Remove{
            entity       = entity,
            component_id = cid,
        })
        return
    }

    remove_component_immediate(world, entity, cid)
}

remove_component :: proc {
    remove_component_entity,
    remove_component_from_type,
}

remove_component_immediate :: proc(world: ^World, entity: EntityID, cid: ComponentID) {
    if !entity_alive(world, entity) do return

    idx := u32(entity_index(entity))
    record := &world.records[idx]
    arch := record.archetype

    if !archetype_has(arch, cid) do return

    // Find or create target archetype via edge cache
    edge: Archetype_Edge
    if cached, ok := arch.remove_edges[cid]; ok {
        edge = cached
    } else {
        // Build new type without cid
        new_type := make([dynamic]ComponentID, context.temp_allocator)
        for c in arch.signature {
            if c != cid {
                append(&new_type, c)
            }
        }
        target := get_or_create_archetype(world, new_type[:])
        // Compute column mappings for both directions
        edge = Archetype_Edge{
            target     = target,
            column_map = compute_column_map(arch, target, world.allocator),
        }
        reverse_edge := Archetype_Edge{
            target     = arch,
            column_map = compute_column_map(target, arch, world.allocator),
        }
        arch.remove_edges[cid] = edge
        target.add_edges[cid] = reverse_edge
    }

    move_entity(world, entity, arch, edge.target, edge.column_map)
}

get_component_entity :: proc(world: ^World, entity: EntityID, $T: typeid) -> ^T {
    if !entity_alive(world, entity) do return nil
    cid, ok := get_component_id(world, T)
    if !ok do return nil
    idx := u32(entity_index(entity))
    record := world.records[idx]
    col_idx := archetype_get_column(record.archetype, cid)
    if col_idx < 0 do return nil
    return column_get(&record.archetype.columns[col_idx], record.row, T)
}

get_component :: proc {
    get_component_entity,
    get_component_from_type,
}

has_component :: proc {
    has_component_type,
    has_component_term,
    has_component_on_type,
}

has_component_type :: proc(world: ^World, entity: EntityID, $T: typeid) -> bool {
    if !entity_alive(world, entity) do return false
    cid, ok := get_component_id(world, T)
    if !ok do return false
    idx := u32(entity_index(entity))
    return archetype_has(world.records[idx].archetype, cid)
}

// Check if entity has a component specified by a Term (useful for pairs)
has_component_term :: proc(world: ^World, entity: EntityID, term: Term) -> bool {
    if !entity_alive(world, entity) do return false
    idx := u32(entity_index(entity))
    arch := world.records[idx].archetype

    switch term.kind {
    case .Component:
        cid, ok := get_component_id_from_typeid(world, term.type_id)
        if !ok do return false
        return archetype_has(arch, cid)

    case .Pair:
        // Resolve the pair to a ComponentID
        cid := resolve_pair(world, term.relation, term.target)
        if cid == 0 do return false
        return archetype_has(arch, cid)

    case .Group:
        // Groups not supported for has_component
        return false
    }
    return false
}

// =============================================================================
// COMPONENT ENABLE/DISABLE (per-entity tracking)
// =============================================================================

disable_component :: proc(world: ^World, entity: EntityID, $T: typeid) {
    if !entity_alive(world, entity) do return

    cid, ok := get_component_id(world, T)
    if !ok do return

    if !has_component(world, entity, T) do return

    // Get or create the inner map for this entity
    if entity not_in world.disabled_components {
        world.disabled_components[entity] = make(map[ComponentID]struct{}, allocator = world.allocator)
    }
    inner := &world.disabled_components[entity]
    inner[cid] = {}
}

enable_component :: proc(world: ^World, entity: EntityID, $T: typeid) {
    if !entity_alive(world, entity) do return

    cid, ok := get_component_id(world, T)
    if !ok do return

    if !has_component(world, entity, T) do return

    if inner, ok := &world.disabled_components[entity]; ok {
        delete_key(inner, cid)
        // Clean up empty inner map
        if len(inner^) == 0 {
            delete(inner^)
            delete_key(&world.disabled_components, entity)
        }
    }
}

is_component_disabled :: proc(world: ^World, entity: EntityID, $T: typeid) -> bool {
    if !entity_alive(world, entity) do return false

    cid, ok := get_component_id(world, T)
    if !ok do return false

    if !has_component(world, entity, T) do return false

    if inner, ok := world.disabled_components[entity]; ok {
        return cid in inner
    }
    return false
}

is_component_enabled :: proc(world: ^World, entity: EntityID, $T: typeid) -> bool {
    return !is_component_disabled(world, entity, T)
}

// =============================================================================
// COMPONENT CAST VARIANTS
// =============================================================================

// Get component and cast to a different type
get_component_cast :: proc(world: ^World, entity: EntityID, $Component: typeid, $CastTo: typeid) -> ^CastTo {
    if !entity_alive(world, entity) do return nil

    cid, ok := get_component_id(world, Component)
    if !ok do return nil

    idx := u32(entity_index(entity))
    record := world.records[idx]
    arch := record.archetype

    col_idx := archetype_get_column(arch, cid)
    if col_idx < 0 do return nil

    return column_get(&arch.columns[col_idx], record.row, CastTo)
}

// =============================================================================
// BATCH COMPONENT OPERATIONS
// =============================================================================

// Add multiple components at once to avoid multiple archetype transitions
add_components :: proc(world: ^World, entity: EntityID, components: ..any) {
    if !entity_alive(world, entity) do return
    if len(components) == 0 do return

    // Defer if iterating - queue individual adds
    if is_iterating(world) || world.is_flushing {
        for comp in components {
            cid := resolve_type(world, comp.id)
            info := world.component_info[cid]
            data_copy: rawptr = nil
            if info.size > 0 && comp.data != nil {
                err: mem.Allocator_Error
                data_copy, err = mem.alloc(info.size, info.alignment, world.allocator)
                if err != nil {
                    panic("ECS: Failed to allocate deferred component data")
                }
                mem.copy(data_copy, comp.data, info.size)
            }
            append(&world.deferred_ops, Deferred_Add{
                entity       = entity,
                component_id = cid,
                data         = data_copy,
                data_size    = info.size,
            })
        }
        return
    }

    idx := u32(entity_index(entity))
    record := &world.records[idx]
    arch := record.archetype

    // Collect all component IDs and check which are new
    new_cids := make([dynamic]ComponentID, context.temp_allocator)
    all_cids := make([dynamic]ComponentID, context.temp_allocator)
    component_data := make(map[ComponentID]rawptr, allocator = context.temp_allocator)

    for comp in components {
        cid := resolve_type(world, comp.id)

        append(&all_cids, cid)
        component_data[cid] = comp.data

        if !archetype_has(arch, cid) {
            append(&new_cids, cid)
        }
    }

    // If no new components, just update existing data
    if len(new_cids) == 0 {
        for cid, data in component_data {
            info := world.component_info[cid]
            if info.size > 0 {
                col_idx := archetype_get_column(arch, cid)
                col := &arch.columns[col_idx]
                column_set(col, record.row, data)
            }
        }
        return
    }

    // Build target type
    new_type := make([dynamic]ComponentID, context.temp_allocator)
    append(&new_type, ..arch.signature)
    append(&new_type, ..new_cids[:])

    target := get_or_create_archetype(world, new_type[:])
    col_map := compute_column_map(arch, target, context.temp_allocator)
    move_entity(world, entity, arch, target, col_map)

    // Set all component data
    record = &world.records[idx]  // Re-fetch
    for cid, data in component_data {
        info := world.component_info[cid]
        if info.size > 0 {
            col_idx := archetype_get_column(target, cid)
            col := &target.columns[col_idx]
            column_set(col, record.row, data)
        }
    }
}

// =============================================================================
// COMPONENT BY ID OPERATIONS
// =============================================================================

add_component_by_id :: proc(world: ^World, entity: EntityID, cid: ComponentID, data: rawptr) {
    // Defer during iteration OR during flush (observers can fire during flush)
    if is_iterating(world) || world.is_flushing {
        // Defer the add during iteration
        info := world.component_info[cid]
        data_copy: rawptr = nil
        if info.size > 0 && data != nil {
            err: mem.Allocator_Error
            data_copy, err = mem.alloc(info.size, info.alignment, world.allocator)
            if err != nil {
                panic("ECS: Failed to allocate deferred component data")
            }
            mem.copy(data_copy, data, info.size)
        }
        append(&world.deferred_ops, Deferred_Add{
            entity       = entity,
            component_id = cid,
            data         = data_copy,
            data_size    = info.size,
        })
        return
    }

    add_component_by_id_immediate(world, entity, cid, data)
}

add_component_by_id_immediate :: proc(world: ^World, entity: EntityID, cid: ComponentID, data: rawptr) {
    if !entity_alive(world, entity) do return

    // Exclusive trait: remove existing pairs with same relation before adding new one
    if is_pair(cid) {
        relation_cid := pair_relation(cid)
        if relation_has_trait_runtime(world, relation_cid, Exclusive) {
            remove_exclusive_pairs(world, entity, relation_cid, cid)
        }
    }

    idx := u32(entity_index(entity))
    record := &world.records[idx]
    arch := record.archetype

    if archetype_has(arch, cid) {
        // Update existing
        info := world.component_info[cid]
        if info.size > 0 && data != nil {
            col_idx := archetype_get_column(arch, cid)
            col := &arch.columns[col_idx]
            column_set(col, record.row, data)
        }
        return
    }

    // Find/create target archetype with pre-computed column mapping
    edge: Archetype_Edge
    if cached, ok := arch.add_edges[cid]; ok {
        edge = cached
    } else {
        new_type := make([dynamic]ComponentID, context.temp_allocator)
        append(&new_type, ..arch.signature)
        append(&new_type, cid)
        target := get_or_create_archetype(world, new_type[:])
        col_map := compute_column_map(arch, target, world.allocator)
        edge = Archetype_Edge{target, col_map}
        arch.add_edges[cid] = edge
        // Reverse edge: removing cid from target goes back to arch
        rev_col_map := compute_column_map(target, arch, world.allocator)
        target.remove_edges[cid] = Archetype_Edge{arch, rev_col_map}
    }

    move_entity(world, entity, arch, edge.target, edge.column_map)

    // Set data if provided
    info := world.component_info[cid]
    if info.size > 0 && data != nil {
        record = &world.records[idx]
        col_idx := archetype_get_column(edge.target, cid)
        col := &edge.target.columns[col_idx]
        column_set(col, record.row, data)
    }
}

remove_component_by_id :: proc(world: ^World, entity: EntityID, cid: ComponentID) {
    // Defer during iteration OR during flush (observers can fire during flush)
    if is_iterating(world) || world.is_flushing {
        // Defer the remove during iteration
        append(&world.deferred_ops, Deferred_Remove{
            entity       = entity,
            component_id = cid,
        })
        return
    }

    remove_component_by_id_immediate(world, entity, cid)
}

remove_component_by_id_immediate :: proc(world: ^World, entity: EntityID, cid: ComponentID) {
    if !entity_alive(world, entity) do return

    idx := u32(entity_index(entity))
    record := &world.records[idx]
    arch := record.archetype

    if !archetype_has(arch, cid) do return

    // Find/create target archetype with pre-computed column mapping
    edge: Archetype_Edge
    if cached, ok := arch.remove_edges[cid]; ok {
        edge = cached
    } else {
        new_type := make([dynamic]ComponentID, context.temp_allocator)
        for c in arch.signature {
            if c != cid {
                append(&new_type, c)
            }
        }
        target := get_or_create_archetype(world, new_type[:])
        col_map := compute_column_map(arch, target, world.allocator)
        edge = Archetype_Edge{target, col_map}
        arch.remove_edges[cid] = edge
        // Reverse edge: adding cid to target goes back to arch
        rev_col_map := compute_column_map(target, arch, world.allocator)
        target.add_edges[cid] = Archetype_Edge{arch, rev_col_map}
    }

    move_entity(world, entity, arch, edge.target, edge.column_map)
}

// =============================================================================
// TYPE ENTITY OPERATIONS
// =============================================================================
// These operations allow attaching components to types (like relation types)
// to enable relation traits like Exclusive and Cascade.
//
// Example:
//   ChildOf :: struct {}
//   Exclusive :: struct {}
//   add_component(world, ChildOf, Exclusive)    // Add tag trait to relation type
//   add_component(world, ChildOf, Exclusive{})  // Also works with value
//   if has_component(world, ChildOf, Exclusive) { ... }

// Get or create the shadow entity for a type
ensure_type_entity :: proc(world: ^World, $T: typeid) -> EntityID {
    if entity, ok := world.type_entities[T]; ok {
        return entity
    }
    entity := add_entity(world)
    world.type_entities[T] = entity
    return entity
}

// Add a component to a type's shadow entity
add_component_to_type :: proc(world: ^World, $Type: typeid, component: $T) {
    type_entity := ensure_type_entity(world, Type)
    add_component_value_impl(world, type_entity, component)
}

// Add a tag component to a type's shadow entity (both args are types)
// Usage: add_component(world, ChildOf, Exclusive)
add_component_type_to_type :: proc(world: ^World, $Type: typeid, $Component: typeid) {
    type_entity := ensure_type_entity(world, Type)
    add_component_value_impl(world, type_entity, Component{})
}

// Check if a type's shadow entity has a component
has_component_on_type :: proc(world: ^World, $Type: typeid, $T: typeid) -> bool {
    entity, ok := world.type_entities[Type]
    if !ok do return false
    return has_component_type(world, entity, T)
}

// Get a component from a type's shadow entity
get_component_from_type :: proc(world: ^World, $Type: typeid, $T: typeid) -> ^T {
    entity, ok := world.type_entities[Type]
    if !ok do return nil
    return get_component_entity(world, entity, T)
}

// Remove a component from a type's shadow entity
remove_component_from_type :: proc(world: ^World, $Type: typeid, $T: typeid) {
    entity, ok := world.type_entities[Type]
    if !ok do return
    remove_component_entity(world, entity, T)
}
