package ecs

// =============================================================================
// RELATIONSHIPS (PAIRS)
// =============================================================================

// Built-in relation traits - attach these to relation types to modify behavior
Exclusive :: struct {}  // Entity can have only one target per relation
Cascade :: struct {}    // Delete entity when its target is deleted

// Pair encoding: relation in upper 16 bits, target in lower 16 bits of ComponentID
// This limits to 65535 component types but allows fast pair operations
PAIR_FLAG : ComponentID : 0x80000000  // High bit marks a pair

// Get component ID for a pair
get_pair_id :: proc(world: ^World, $R, $T: typeid) -> ComponentID {
    r_cid := ensure_component(world, R)
    t_cid := ensure_component(world, T)
    return make_pair_id(r_cid, t_cid)
}

get_pair_id_relation_entity :: proc(world: ^World, $R: typeid, target: EntityID) -> ComponentID {
    r_cid := ensure_component(world, R)
    // Use entity index as target component id (with flag to distinguish)
    t_id := ComponentID(entity_index(target))
    return make_pair_id(r_cid, t_id)
}

get_pair_id_entity_target :: proc(world: ^World, relation: EntityID, $T: typeid) -> ComponentID {
    r_id := ComponentID(entity_index(relation))
    t_cid := ensure_component(world, T)
    return make_pair_id(r_id, t_cid)
}

get_pair_id_entities :: proc(world: ^World, relation: EntityID, target: EntityID) -> ComponentID {
    r_id := ComponentID(entity_index(relation))
    t_id := ComponentID(entity_index(target))
    return make_pair_id(r_id, t_id)
}

make_pair_id :: proc(relation, target: ComponentID) -> ComponentID {
    if relation > PAIR_RELATION_MAX {
        panic("ECS: Relation ComponentID exceeds pair encoding limit (max 32767)")
    }
    if target > PAIR_TARGET_MAX {
        panic("ECS: Target ComponentID exceeds pair encoding limit (max 65535)")
    }
    return PAIR_FLAG | ((relation & PAIR_RELATION_MAX) << PAIR_TARGET_BITS) | (target & PAIR_TARGET_MAX)
}

pair_relation :: proc(pair_id: ComponentID) -> ComponentID {
    return (pair_id >> PAIR_TARGET_BITS) & PAIR_RELATION_MAX
}

pair_target :: proc(pair_id: ComponentID) -> ComponentID {
    return pair_id & PAIR_TARGET_MAX
}

is_pair :: proc(cid: ComponentID) -> bool {
    return (cid & PAIR_FLAG) != 0
}

// Add a relationship - reads like a sentence: "entity Relation target"
add_pair :: proc {
    // Tag pairs (no relation data)
    add_pair_types,           // (world, entity, R, T) - two types
    add_pair_type_entity,     // (world, entity, R, target) - type relation, entity target
    add_pair_entity_type,     // (world, entity, relation, T) - entity relation, type target
    add_pair_entities,        // (world, entity, relation, target) - two entities
    // Data pairs (relation type inferred from data)
    add_pair_data_type,       // (world, entity, data, T) - data, type target
    add_pair_data_entity,     // (world, entity, data, target) - data, entity target
    // Note: ambiguous when 3rd arg is EntityID + 4th is typeid - use explicit proc
}

// Tag pair: type relation + type target, no data
add_pair_types :: proc(world: ^World, entity: EntityID, $R, $T: typeid) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id(world, R, T)
    ensure_pair_registered(world, pair_cid, size_of(R))
    add_component_by_id(world, entity, pair_cid, nil)
}

// Tag pair: type relation + entity target, no data
add_pair_type_entity :: proc(world: ^World, entity: EntityID, $R: typeid, target: EntityID) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id_relation_entity(world, R, target)
    ensure_pair_registered(world, pair_cid, size_of(R))
    add_component_by_id(world, entity, pair_cid, nil)
}

// Tag pair: entity relation + type target, no data
add_pair_entity_type :: proc(world: ^World, entity: EntityID, relation: EntityID, $T: typeid) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id_entity_target(world, relation, T)
    ensure_pair_registered(world, pair_cid, 0)  // No data when relation is entity
    add_component_by_id(world, entity, pair_cid, nil)
}

// Tag pair: entity relation + entity target, no data
add_pair_entities :: proc(world: ^World, entity: EntityID, relation: EntityID, target: EntityID) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id_entities(world, relation, target)
    ensure_pair_registered(world, pair_cid, 0)  // No data for pure entity pairs
    add_component_by_id(world, entity, pair_cid, nil)
}

// Data pair: "entity Data target" - reads like a sentence
add_pair_data_type :: proc(world: ^World, entity: EntityID, data: $R, $T: typeid) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id(world, R, T)
    ensure_pair_registered(world, pair_cid, size_of(R))
    local := data
    add_component_by_id(world, entity, pair_cid, &local)
}

// Data pair: "entity Data target" - reads like a sentence
add_pair_data_entity :: proc(world: ^World, entity: EntityID, data: $R, target: EntityID) {
    if !entity_alive(world, entity) do return

    pair_cid := get_pair_id_relation_entity(world, R, target)
    ensure_pair_registered(world, pair_cid, size_of(R))
    local := data
    add_component_by_id(world, entity, pair_cid, &local)
}

ensure_pair_registered :: proc(world: ^World, pair_cid: ComponentID, data_size: int) {
    if _, ok := world.component_info[pair_cid]; !ok {
        world.component_info[pair_cid] = Component_Info{
            size      = data_size,
            alignment = DEFAULT_PAIR_ALIGNMENT,
            type_info = nil,
        }
    }
}

// Remove a relationship
remove_pair :: proc {
    remove_pair_types,
    remove_pair_relation_entity,
    remove_pair_entity_target,
    remove_pair_entities,
}

remove_pair_types :: proc(world: ^World, entity: EntityID, $R, $T: typeid) {
    if !entity_alive(world, entity) do return
    pair_cid := get_pair_id(world, R, T)
    remove_component_by_id(world, entity, pair_cid)
}

remove_pair_relation_entity :: proc(world: ^World, entity: EntityID, $R: typeid, target: EntityID) {
    if !entity_alive(world, entity) do return
    pair_cid := get_pair_id_relation_entity(world, R, target)
    remove_component_by_id(world, entity, pair_cid)
}

remove_pair_entity_target :: proc(world: ^World, entity: EntityID, relation: EntityID, $T: typeid) {
    if !entity_alive(world, entity) do return
    pair_cid := get_pair_id_entity_target(world, relation, T)
    remove_component_by_id(world, entity, pair_cid)
}

remove_pair_entities :: proc(world: ^World, entity: EntityID, relation: EntityID, target: EntityID) {
    if !entity_alive(world, entity) do return
    pair_cid := get_pair_id_entities(world, relation, target)
    remove_component_by_id(world, entity, pair_cid)
}

// Get relationship data
get_pair :: proc {
    get_pair_types,
    get_pair_relation_entity,
}

get_pair_types :: proc(world: ^World, entity: EntityID, $R, $T: typeid) -> ^R {
    if !entity_alive(world, entity) do return nil

    pair_cid := get_pair_id(world, R, T)

    idx := u32(entity_index(entity))
    record := world.records[idx]
    arch := record.archetype

    col_idx := archetype_get_column(arch, pair_cid)
    if col_idx < 0 do return nil

    return column_get(&arch.columns[col_idx], record.row, R)
}

get_pair_relation_entity :: proc(world: ^World, entity: EntityID, $R: typeid, target: EntityID) -> ^R {
    if !entity_alive(world, entity) do return nil

    pair_cid := get_pair_id_relation_entity(world, R, target)

    idx := u32(entity_index(entity))
    record := world.records[idx]
    arch := record.archetype

    col_idx := archetype_get_column(arch, pair_cid)
    if col_idx < 0 do return nil

    return column_get(&arch.columns[col_idx], record.row, R)
}

// Check if entity has relationship
has_pair :: proc {
    has_pair_types,
    has_pair_relation_entity,
    has_pair_entity_target,
    has_pair_entities,
}

has_pair_by_id :: proc(world: ^World, entity: EntityID, pair_cid: ComponentID) -> bool {
    if !entity_alive(world, entity) do return false
    idx := u32(entity_index(entity))
    return archetype_has(world.records[idx].archetype, pair_cid)
}

has_pair_types :: proc(world: ^World, entity: EntityID, $R, $T: typeid) -> bool {
    pair_cid := get_pair_id(world, R, T)
    return has_pair_by_id(world, entity, pair_cid)
}

has_pair_relation_entity :: proc(world: ^World, entity: EntityID, $R: typeid, target: EntityID) -> bool {
    pair_cid := get_pair_id_relation_entity(world, R, target)
    return has_pair_by_id(world, entity, pair_cid)
}

has_pair_entity_target :: proc(world: ^World, entity: EntityID, relation: EntityID, $T: typeid) -> bool {
    pair_cid := get_pair_id_entity_target(world, relation, T)
    return has_pair_by_id(world, entity, pair_cid)
}

has_pair_entities :: proc(world: ^World, entity: EntityID, relation: EntityID, target: EntityID) -> bool {
    pair_cid := get_pair_id_entities(world, relation, target)
    return has_pair_by_id(world, entity, pair_cid)
}

// Get all targets of a relationship for an entity
// Returns a slice of entity IDs (allocated with temp_allocator)
// Usage: for target in get_relation_targets(world, entity, ChildOf) { ... }
get_relation_targets :: proc(world: ^World, entity: EntityID, $R: typeid) -> []EntityID {
    if !entity_alive(world, entity) do return nil

    idx := u32(entity_index(entity))
    arch := world.records[idx].archetype
    if arch == nil do return nil

    r_cid := ensure_component(world, R)
    lower := PAIR_FLAG | ((r_cid & PAIR_RELATION_MAX) << PAIR_TARGET_BITS)
    upper := lower | PAIR_TARGET_MAX

    targets := make([dynamic]EntityID, context.temp_allocator)
    for cid in arch.signature {
        if cid >= lower && cid <= upper {
            target_cid := pair_target(cid)
            append(&targets, EntityID(target_cid))
        }
    }
    return targets[:]
}

// =============================================================================
// RELATION TRAIT HELPERS
// =============================================================================

// Check if a relation (by ComponentID) has a trait attached
// Returns false for entity-based relations (they don't have type entities)
relation_has_trait :: proc(world: ^World, relation_cid: ComponentID, $Trait: typeid) -> bool {
    // O(1) reverse lookup
    tid, ok := world.component_to_type[relation_cid]
    if !ok do return false  // Entity relations don't have traits

    // Check if the type entity has the trait
    type_entity, type_ok := world.type_entities[tid]
    if !type_ok do return false

    return has_component_type(world, type_entity, Trait)
}

// Runtime version that takes typeid as a value
relation_has_trait_runtime :: proc(world: ^World, relation_cid: ComponentID, trait: typeid) -> bool {
    // O(1) reverse lookup
    tid, ok := world.component_to_type[relation_cid]
    if !ok do return false  // Entity relations don't have traits

    // Check if the type entity has the trait
    type_entity, type_ok := world.type_entities[tid]
    if !type_ok do return false

    trait_cid, trait_ok := world.type_to_component[trait]
    if !trait_ok do return false

    return archetype_has(world.records[u32(entity_index(type_entity))].archetype, trait_cid)
}

// Remove all pairs with the given relation except the one we're keeping
// Used by Exclusive trait to ensure only one target per relation
remove_exclusive_pairs :: proc(world: ^World, entity: EntityID, relation_cid: ComponentID, keep_pair: ComponentID) {
    idx := u32(entity_index(entity))
    arch := world.records[idx].archetype
    if arch == nil do return

    // Find all pairs with this relation
    pairs := archetype_find_all_pairs_with_relation(arch, relation_cid, context.temp_allocator)

    for pair_cid in pairs {
        if pair_cid != keep_pair {
            remove_component_by_id_immediate(world, entity, pair_cid)
        }
    }
}

// Delete all entities that have a Cascade relation targeting the given entity
cascade_delete_dependents :: proc(world: ^World, target_entity: EntityID) {
    target_cid := ComponentID(entity_index(target_entity))
    to_delete := make([dynamic]EntityID, context.temp_allocator)

    // Iterate all archetypes looking for pairs targeting this entity
    for arch in world.archetypes {
        for cid in arch.signature {
            if !is_pair(cid) do continue
            if pair_target(cid) != target_cid do continue

            // Check if this relation has Cascade trait
            relation_cid := pair_relation(cid)
            if !relation_has_trait_runtime(world, relation_cid, Cascade) do continue

            // Collect all entities in this archetype for deletion
            for e in arch.entities {
                append(&to_delete, e)
            }
            break  // Found cascade pair, all entities collected from this archetype
        }
    }

    // Delete collected entities (use remove_entity for proper deferral)
    for e in to_delete {
        if entity_alive(world, e) {
            remove_entity(world, e)
        }
    }
}
