package ecs

// =============================================================================
// CORE TYPES
// =============================================================================

EntityID :: distinct u64
ComponentID :: distinct u32
ArchetypeID :: distinct u64
ObserverID :: distinct u32

// =============================================================================
// DECLARATIVE QUERY TYPES
// =============================================================================

// Wildcards (values, not types to instantiate)
Wildcard_T :: distinct struct {}
Any_T :: distinct struct {}
Wildcard : Wildcard_T : {}
Any : Any_T : {}

// Query variables for capturing matched values
Var :: distinct u8
This : Var : 254    // Primary matched entity
None : Var : 255    // No capture (used as default)

// What a pair target can be
Pair_Target :: union {
    typeid,
    EntityID,
    Wildcard_T,
    Any_T,
    Var,
}

// Traversal direction for relationship traversal
Traverse :: enum { None, Up, Down }

// Group operators for combining terms
Group_Op :: enum { All, Any, None }  // None = "match none of these"

// Term kind discriminator
Term_Kind :: enum { Component, Pair, Group }

// Declarative query term - stores typeid, resolved at query time
Term :: struct {
    // What to match
    kind:            Term_Kind,
    type_id:         typeid,        // Component type (for .Component)
    relation:        typeid,        // Pair relation type (for .Pair when relation is a type)
    relation_entity: EntityID,      // Pair relation entity (for .Pair when relation is an entity)
    target:          Pair_Target,   // Pair target (for .Pair)

    // Modifiers
    source:       Var,           // Which entity to match on (default: This)
    capture_to:   Var,           // Capture wildcard match (default: None)
    traverse_dir: Traverse,      // Traversal direction
    traverse_rel: typeid,        // Relationship to traverse
    negate:       bool,          // Negation (for not())
    cascade:      bool,          // Enable cascade ordering (depth-ordered iteration)

    // Grouping
    group_op:     Group_Op,
    group_terms:  []Term,        // Nested terms for groups
}

// Entity ID encoding: [generation:16][index:48]
ENTITY_INDEX_BITS :: 48
ENTITY_GEN_BITS :: 16
ENTITY_INDEX_MASK : u64 : (1 << ENTITY_INDEX_BITS) - 1
ENTITY_GEN_MASK : u16 : (1 << ENTITY_GEN_BITS) - 1

// Query variable binding limits
MAX_QUERY_BINDINGS :: 8

// Pair ID encoding limits (relation: 15 bits, target: 16 bits)
PAIR_RELATION_BITS :: 15
PAIR_TARGET_BITS :: 16
PAIR_RELATION_MAX : ComponentID : (1 << PAIR_RELATION_BITS) - 1  // 32767
PAIR_TARGET_MAX : ComponentID : (1 << PAIR_TARGET_BITS) - 1      // 65535

// Entity and pair constants
RESERVED_ENTITY_SLOT :: 0
FIRST_ENTITY_INDEX :: 1
DEFAULT_PAIR_ALIGNMENT :: align_of(rawptr)

// Sparse-dense entity index (like flecs/bitecs)
// - dense[0..alive_count-1] = alive entities (packed)
// - dense[alive_count..] = dead/recyclable entities
// - sparse[entity_index] = position in dense array
Entity_Index :: struct {
    dense:       [dynamic]EntityID,  // Densely packed entity IDs
    sparse:      [dynamic]u32,       // entity_index -> dense position
    alive_count: u32,                // Partition point in dense
    max_id:      u32,                // Highest entity index ever assigned
}

entity_index :: #force_inline proc(e: EntityID) -> u64 {
    return u64(e) & ENTITY_INDEX_MASK
}

entity_generation :: #force_inline proc(e: EntityID) -> u16 {
    return u16(u64(e) >> ENTITY_INDEX_BITS)
}

make_entity_id :: #force_inline proc(index: u64, gen: u16) -> EntityID {
    return EntityID(index | (u64(gen) << ENTITY_INDEX_BITS))
}
