package ecs

import "core:slice"
import "core:sync"

// =============================================================================
// QUERY SYSTEM - DECLARATIVE API
// =============================================================================

// Usage: query(world, {Position, Velocity, not(Dead)})
//        query(world, {Position, Velocity})  // plain typeids are simple "has component"

// =============================================================================
// TERM ENCODING SYSTEM
// =============================================================================
//
// WHY: We want this clean API where types and operators mix freely:
//
//     query(world, {Position, Velocity, not(Dead), or(Flying, Swimming)})
//
// PROBLEM: Odin auto-converts type names to typeid ONLY when target type is
// exactly `typeid` or `[]typeid`. With a union like `union{Term, typeid}`,
// Odin can't infer which variant, so users would need explicit `typeid_of()`.
//
// SOLUTION: Use `[]typeid` as the API. Plain types pass through as typeids.
// Term constructors (not, or, pair, etc.) store their Term in a global array
// and return a pointer into it transmuted as a typeid.
//
// ENCODING: Real typeids point into the runtime type_info table. Encoded terms
// point into our `encoded_terms` array. The memory ranges never overlap, so
// a simple bounds check distinguishes them with zero false positives.
//
// WHY GLOBAL (not thread-local): Parallel test runners execute tests across
// threads. Thread-local storage would break when terms encoded in thread A
// are decoded in thread B. Global atomic storage ensures correctness.

// Global term storage - fixed size array, thread-safe via atomic counter
MAX_ENCODED_TERMS :: 65536
@(private="file")
encoded_terms: [MAX_ENCODED_TERMS]Term
@(private="file")
encoded_term_count: u32  // Atomic counter

// Encode a Term into a typeid by storing it globally and returning a pointer
encode_term :: proc(t: Term) -> typeid {
    idx := sync.atomic_add(&encoded_term_count, 1)
    if idx >= MAX_ENCODED_TERMS {
        panic("ECS: Too many encoded query terms (max 65536)")
    }
    encoded_terms[idx] = t
    return transmute(typeid)&encoded_terms[idx]
}

// Check if a typeid is an encoded term (pointer into our array)
is_encoded :: proc(t: typeid) -> bool {
    ptr := transmute(uintptr)t
    base := uintptr(&encoded_terms[0])
    return ptr >= base && ptr < base + size_of(encoded_terms)
}

// Decode a typeid back to a Term
decode_term :: proc(t: typeid) -> Term {
    if !is_encoded(t) {
        return term_from_typeid(t)
    }
    return (transmute(^Term)t)^
}

// Convert []typeid to []Term for internal use
typeids_to_terms :: proc(types: []typeid) -> []Term {
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    // All encoded terms have been decoded (copied out) - slots are dead.
    // Reset the bump allocator so it never fills up.
    sync.atomic_store(&encoded_term_count, 0)
    return terms
}

// Reset encoded term counter - now called automatically by typeids_to_terms.
// Kept as public API for backward compatibility.
reset_encoded_terms :: proc() {
    sync.atomic_store(&encoded_term_count, 0)
}

// Runtime typeid to Term conversion
term_from_typeid :: proc(T: typeid) -> Term {
    return Term{
        kind       = .Component,
        type_id    = T,
        source     = This,
        capture_to = None,
    }
}

// Pair term constructors - used for both queries and add_component
pair :: proc {
    pair_types,
    pair_type_entity,
    pair_entity_type,
    pair_entities,
    pair_wildcard,
    pair_any,
    pair_var,
}

pair_types :: proc($R, $T: typeid) -> typeid {
    return encode_term(Term{
        kind     = .Pair,
        relation = R,
        target   = Pair_Target(typeid_of(T)),
        source   = This,
        capture_to = None,
    })
}

pair_type_entity :: proc($R: typeid, target: EntityID) -> typeid {
    return encode_term(Term{
        kind     = .Pair,
        relation = R,
        target   = target,
        source   = This,
        capture_to = None,
    })
}

pair_entity_type :: proc(relation: EntityID, $T: typeid) -> typeid {
    return encode_term(Term{
        kind            = .Pair,
        relation        = nil,
        relation_entity = relation,
        target          = Pair_Target(typeid_of(T)),
        source          = This,
        capture_to      = None,
    })
}

pair_entities :: proc(relation: EntityID, target: EntityID) -> typeid {
    return encode_term(Term{
        kind            = .Pair,
        relation        = nil,
        relation_entity = relation,
        target          = target,
        source          = This,
        capture_to      = None,
    })
}

pair_wildcard :: proc($R: typeid, _: Wildcard_T) -> typeid {
    return encode_term(Term{
        kind     = .Pair,
        relation = R,
        target   = Wildcard,
        source   = This,
        capture_to = None,
    })
}

pair_any :: proc($R: typeid, _: Any_T) -> typeid {
    return encode_term(Term{
        kind     = .Pair,
        relation = R,
        target   = Any,
        source   = This,
        capture_to = None,
    })
}

pair_var :: proc($R: typeid, v: Var) -> typeid {
    return encode_term(Term{
        kind     = .Pair,
        relation = R,
        target   = v,
        source   = This,
        capture_to = None,
    })
}

// =============================================================================
// HIERARCHY/CASCADE TERM - DEPTH-ORDERED ITERATION
// =============================================================================
//
// The hierarchy()/cascade() modifier enables topological iteration for hierarchical relations.
// Entities are iterated in depth order: depth 0 (roots), then depth 1, etc.
// This ensures parents are always processed before their children.
//
// Usage:
//   for arch in ecs.query(world, {ecs.hierarchy(ChildOf)}) {
//       // Parents processed before children
//   }
//
// No special trait setup required - depths are computed on-demand.

hierarchy :: proc($R: typeid) -> typeid {
    return encode_term(Term{
        kind       = .Pair,
        relation   = R,
        target     = Wildcard,
        source     = This,
        capture_to = None,
        cascade    = true,
    })
}

// Alias for hierarchy()
cascade :: hierarchy

// Term modifiers - take a typeid (plain or encoded), return encoded typeid

on :: proc(v: Var, T: typeid) -> typeid {
    t := decode_term(T)
    t.source = v
    return encode_term(t)
}

capture :: proc(v: Var, T: typeid) -> typeid {
    t := decode_term(T)
    t.capture_to = v
    return encode_term(t)
}

// Traversal modifiers - take typeid (plain or encoded), return encoded typeid

up :: proc(T: typeid) -> typeid {
    t := decode_term(T)
    t.traverse_dir = .Up
    return encode_term(t)
}

up_with :: proc(T: typeid, $R: typeid) -> typeid {
    t := decode_term(T)
    t.traverse_dir = .Up
    t.traverse_rel = R
    return encode_term(t)
}

down :: proc(T: typeid) -> typeid {
    t := decode_term(T)
    t.traverse_dir = .Down
    return encode_term(t)
}

down_with :: proc(T: typeid, $R: typeid) -> typeid {
    t := decode_term(T)
    t.traverse_dir = .Down
    t.traverse_rel = R
    return encode_term(t)
}

// =============================================================================
// GROUP CONSTRUCTORS: and/all, or/any, not/none
// =============================================================================
//
// NOTE: Group terms use temp_allocator for the nested term slice. This is
// intentional - Terms are designed for immediate use in queries, not long-term
// storage. The query system processes Terms and caches ComponentIDs, not Terms.

// AND - require all (aliases: and, all)
// Takes variadic typeids (plain or encoded), returns encoded typeid
and :: proc(types: ..typeid) -> typeid {
    if len(types) == 1 {
        return types[0]  // Single item, return as-is (could be plain or encoded)
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    return encode_term(Term{
        kind        = .Group,
        group_op    = .All,
        group_terms = terms,
        source      = This,
        capture_to  = None,
    })
}

// Alias for and()
all :: and

// OR - require any (aliases: or, some)
// Takes variadic typeids (plain or encoded), returns encoded typeid
or :: proc(types: ..typeid) -> typeid {
    if len(types) == 1 {
        return types[0]
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    return encode_term(Term{
        kind        = .Group,
        group_op    = .Any,
        group_terms = terms,
        source      = This,
        capture_to  = None,
    })
}

// Alias for or()
some :: or

// NOT/NONE - require none (aliases: not, none)
// Single item: negates it. Multiple items: matches none of them.
// Takes variadic typeids (plain or encoded), returns encoded typeid
not :: proc(types: ..typeid) -> typeid {
    if len(types) == 1 {
        t := decode_term(types[0])
        t.negate = true
        return encode_term(t)
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = decode_term(types[i])
    }
    return encode_term(Term{
        kind        = .Group,
        group_op    = .None,
        group_terms = terms,
        source      = This,
        capture_to  = None,
    })
}

// Alias for not()
none :: not

// =============================================================================
// QUERY TERM RESOLUTION
// =============================================================================

// Resolve typeid to ComponentID, registering if needed
resolve_type :: proc(world: ^World, tid: typeid) -> ComponentID {
    if tid == nil do return 0
    if cid, ok := world.type_to_component[tid]; ok {
        return cid
    }
    // Auto-register using runtime type_info
    return register_component_dynamic(world, tid)
}

// Runtime registration for types not known at compile time
register_component_dynamic :: proc(world: ^World, tid: typeid) -> ComponentID {
    cid := world.next_component_id
    world.next_component_id += 1

    ti := type_info_of(tid)
    world.component_info[cid] = Component_Info{
        size      = ti.size,
        alignment = ti.align,
        type_info = ti,
    }
    world.type_to_component[tid] = cid
    world.component_to_type[cid] = tid  // Reverse lookup for O(1) trait checks
    return cid
}

// Resolve pair target to ComponentID
resolve_pair_target :: proc(world: ^World, target: Pair_Target) -> ComponentID {
    switch t in target {
    case typeid:
        return resolve_type(world, t)
    case EntityID:
        return ComponentID(entity_index(t))
    case Wildcard_T:
        return 0  // Special handling for wildcards
    case Any_T:
        return 0  // Special handling for any
    case Var:
        return 0  // Variables resolved during matching
    }
    return 0
}

// Resolve a pair term to a ComponentID
resolve_pair :: proc(world: ^World, relation: typeid, target: Pair_Target) -> ComponentID {
    r_cid := resolve_type(world, relation)

    switch t in target {
    case typeid:
        t_cid := resolve_type(world, t)
        return make_pair_id(r_cid, t_cid)
    case EntityID:
        t_id := ComponentID(entity_index(t))
        return make_pair_id(r_cid, t_id)
    case Wildcard_T, Any_T, Var:
        // For wildcards/any/vars, we need special handling in query matching
        // Return a partial pair ID that we'll match against
        return make_pair_id(r_cid, 0) | PAIR_FLAG
    }
    return 0
}

// Resolve a pair term with entity relation to a ComponentID
resolve_pair_entity_relation :: proc(world: ^World, relation: EntityID, target: Pair_Target) -> ComponentID {
    r_cid := ComponentID(entity_index(relation))

    switch t in target {
    case typeid:
        t_cid := resolve_type(world, t)
        return make_pair_id(r_cid, t_cid)
    case EntityID:
        t_id := ComponentID(entity_index(t))
        return make_pair_id(r_cid, t_id)
    case Wildcard_T, Any_T, Var:
        return make_pair_id(r_cid, 0) | PAIR_FLAG
    }
    return 0
}

// =============================================================================
// QUERY EXECUTION
// =============================================================================

// Query Result with variable bindings
Query_Result :: struct {
    entity:    EntityID,
    archetype: ^Archetype,
    row:       int,
    bindings:  [MAX_QUERY_BINDINGS]EntityID,   // v0..v7 bound values
}

// Query flags for optional behaviors
Query_Flags :: bit_set[Query_Flag]
Query_Flag :: enum {
    Include_Disabled,  // Include entities with disabled required components
}

// =============================================================================
// ARCHETYPE QUERY - Direct iteration with automatic cleanup
// =============================================================================
//
// Usage (one-line - no deferred safety):
//   for arch in ecs.query(world, {Position, Velocity}) {
//       positions := ecs.get_table(world, arch, Position)
//       // ...
//   }
//
// Usage (two-line - deferred safety for structural changes):
//   q := ecs.query(world, {Position, Velocity})
//   for arch in q {
//       // Safe to add/remove components, destroy entities (changes are deferred)
//   }
//   // Cleanup is automatic via @(deferred_in) - safe to break/return early

// Query is a distinct slice of archetype pointers - directly iterable in for-in.
// Two usage patterns with the same query() function:
//
//   One-line (no deferred safety - structural changes are immediate):
//     for arch in ecs.query(world, {Position, Velocity}) { ... }
//
//   Two-line (deferred safety - structural changes batched until scope exit):
//     q := ecs.query(world, {Position, Velocity})
//     for arch in q { ... }
//
Query :: distinct []^Archetype

// Automatic cleanup - called via @(deferred_in) when query() scope exits.
// With one-line pattern this fires per-iteration (harmless due to clamp).
// With two-line pattern this fires once at scope exit (full deferred safety).
query_auto_cleanup :: proc(world: ^World, types: []typeid) {
    if world.iteration_depth > 0 {
        world.iteration_depth -= 1
        if world.iteration_depth == 0 {
            flush_deferred(world)
        }
    }
}

// Wildcard term info for matching pairs with wildcards
Wildcard_Term :: struct {
    relation_cid: ComponentID,  // The relation to match
    negate:       bool,         // Whether this is a NOT term
}

// Capture info for populating bindings
Capture_Info :: struct {
    relation_cid: ComponentID,  // Relation to match for capture
    var_index:    u8,           // Which binding slot (v0..v7)
}

// Any_of group - at least one term must match
Any_Of_Group :: struct {
    terms: []Term,  // Original terms
}

// Query context - collects all info needed for matching
Query_Context :: struct {
    required:        [dynamic]ComponentID,  // Exact match required
    excluded:        [dynamic]ComponentID,  // Exact match excluded
    wildcard_terms:  [dynamic]Wildcard_Term,  // Wildcard pair matching
    any_of_groups:   [dynamic]Any_Of_Group,   // Any_of group matching
    captures:        [dynamic]Capture_Info,   // Variable captures
    cascade_rel:     ComponentID,             // Cascade relation (0 if none)
}

// Query_Context uses temp_allocator - no manual cleanup required.
query_context_init :: proc() -> Query_Context {
    return Query_Context{
        required       = make([dynamic]ComponentID, context.temp_allocator),
        excluded       = make([dynamic]ComponentID, context.temp_allocator),
        wildcard_terms = make([dynamic]Wildcard_Term, context.temp_allocator),
        any_of_groups  = make([dynamic]Any_Of_Group, context.temp_allocator),
        captures       = make([dynamic]Capture_Info, context.temp_allocator),
    }
}

// Query execution (raw) - returns matching archetypes without iteration protection
// NOTE: Flushes pending deferred ops before returning results.
// This function does NOT enter iteration mode - structural changes are immediate.
// For internal use or when you know you won't modify entities during iteration.
//
// Usage: query_raw(world, {Position, Velocity, not(Dead)})
query_raw :: proc(world: ^World, types: []typeid) -> []^Archetype {
    return query_with_flags(world, types, {})
}

// Query with automatic cleanup via @(deferred_in).
//
// Usage:
//   for arch in ecs.query(world, {Position, Velocity}) { ... }
//   for arch in ecs.query(world, {Position, ecs.not(Dead)}) { ... }
@(deferred_in=query_auto_cleanup)
query :: proc(world: ^World, types: []typeid) -> Query {
    // Convert typeids to Terms (term_storage holds encoded terms from constructors)
    terms := typeids_to_terms(types)

    // Flush before entering iteration - only safe when not already iterating
    if world.iteration_depth == 0 {
        flush_deferred(world)
    }
    world.iteration_depth += 1

    cached := query_cached_internal(world, terms, {})

    // Cascade: build depth-ordered slice so for-in iterates parents before children
    if cached.depth_groups != nil {
        ordered := make([dynamic]^Archetype, context.temp_allocator)
        for &group in cached.depth_groups {
            for idx in group {
                append(&ordered, cached.archetypes[idx])
            }
        }
        result := Query(ordered[:])
        // With the one-line `for arch in query(...)` pattern, @(deferred_in)
        // fires per-iteration. If there are zero results, the for body never
        // runs and cleanup never fires — so undo the increment here.
        if len(result) == 0 {
            world.iteration_depth -= 1
            if world.iteration_depth == 0 {
                flush_deferred(world)
            }
        }
        return result
    }

    result := Query(cached.archetypes[:])
    // Same fix for the non-cascade path.
    if len(result) == 0 {
        world.iteration_depth -= 1
        if world.iteration_depth == 0 {
            flush_deferred(world)
        }
    }
    return result
}

// Query with optional flags (public API - accepts []typeid)
query_with_flags :: proc(world: ^World, types: []typeid, flags: Query_Flags) -> []^Archetype {
    // Convert typeids to Terms
    terms := typeids_to_terms(types)
    return query_with_flags_internal(world, terms, flags)
}

// Internal query implementation (works with []Term directly) - returns archetypes only
query_with_flags_internal :: proc(world: ^World, terms: []Term, flags: Query_Flags) -> []^Archetype {
    cached := query_cached_internal(world, terms, flags)
    return cached.archetypes[:]
}

// Empty query result for nil cases
@(private)
_empty_cached_query: Cached_Query

// Internal query implementation that returns the full cached query
query_cached_internal :: proc(world: ^World, terms: []Term, flags: Query_Flags) -> ^Cached_Query {
    // Note: Flushing is handled by query() before incrementing iteration_depth
    // This prevents nested queries from flushing mid-iteration

    if len(terms) == 0 {
        return &_empty_cached_query
    }

    // Build query context
    ctx := query_context_init()
    process_terms_ctx(world, terms, &ctx)

    // Check cache
    key := hash_query_context(&ctx)
    if cached, ok := &world.query_cache^[key]; ok {
        if cached.generation == world.archetype_generation {
            return cached  // Cache hit
        }
        // Stale - clear old result and free old slices
        clear(&cached.archetypes)
        delete(cached.captures, world.cache_allocator)
        delete(cached.required_cids, world.cache_allocator)
        cached.captures = nil
        cached.required_cids = nil
        // Free old depth_groups
        if cached.depth_groups != nil {
            for &group in cached.depth_groups {
                delete(group)
            }
            delete(cached.depth_groups, world.cache_allocator)
            cached.depth_groups = nil
        }
    }

    // Cache miss or stale - scan archetypes
    if key not_in world.query_cache^ {
        world.query_cache^[key] = Cached_Query{
            archetypes = make([dynamic]^Archetype, world.cache_allocator),
            generation = 0,
        }
    }
    cached := &world.query_cache^[key]

    // Free old depth_groups if present
    if cached.depth_groups != nil {
        for &group in cached.depth_groups {
            delete(group)
        }
        delete(cached.depth_groups, world.cache_allocator)
        cached.depth_groups = nil
    }

    for arch in world.archetypes {
        if archetype_matches_query(world, arch, &ctx) {
            append(&cached.archetypes, arch)
        }
    }
    cached.generation = world.archetype_generation

    // Clone captures and required_cids with cache_allocator for cache persistence
    cached.captures = slice.clone(ctx.captures[:], world.cache_allocator)
    cached.required_cids = slice.clone(ctx.required[:], world.cache_allocator)

    // Build cascade depth groups if cascade is enabled
    cached.cascade_rel = ctx.cascade_rel
    if ctx.cascade_rel != 0 {
        build_cascade_depth_groups(world, cached, ctx.cascade_rel)
    }

    return cached
}

// Build depth-grouped archetype indices for cascade queries
build_cascade_depth_groups :: proc(world: ^World, cached: ^Cached_Query, relation_cid: ComponentID) {
    if len(cached.archetypes) == 0 {
        return
    }

    // First pass: find max depth across all matching archetypes
    max_depth: u16 = 0
    for arch_idx := 0; arch_idx < len(cached.archetypes); arch_idx += 1 {
        arch := cached.archetypes[arch_idx]
        for entity in arch.entities {
            depth := compute_hierarchy_depth(world, entity, relation_cid)
            if depth > max_depth {
                max_depth = depth
            }
        }
    }
    cached.max_depth = max_depth

    // Allocate depth groups (max_depth + 1 levels: 0 to max_depth)
    cached.depth_groups = make([][dynamic]int, int(max_depth) + 1, world.cache_allocator)
    for i := 0; i < len(cached.depth_groups); i += 1 {
        cached.depth_groups[i] = make([dynamic]int, world.cache_allocator)
    }

    // Second pass: group archetypes by their minimum entity depth
    // (An archetype's position in iteration is determined by min depth of its entities)
    for arch_idx := 0; arch_idx < len(cached.archetypes); arch_idx += 1 {
        arch := cached.archetypes[arch_idx]

        // Find minimum depth of entities in this archetype
        min_depth: u16 = max(u16)
        has_entities := false
        for entity in arch.entities {
            depth := compute_hierarchy_depth(world, entity, relation_cid)
            has_entities = true
            if depth < min_depth {
                min_depth = depth
            }
        }

        // If no entities, treat as depth 0
        if !has_entities {
            min_depth = 0
        }

        // Add archetype index to appropriate depth group
        append(&cached.depth_groups[min_depth], arch_idx)
    }
}

// Check if archetype matches all query requirements
archetype_matches_query :: proc(world: ^World, arch: ^Archetype, ctx: ^Query_Context) -> bool {
    // Check all exact required present
    for cid in ctx.required {
        if !archetype_has(arch, cid) {
            return false
        }
    }

    // Check none exact excluded present
    for cid in ctx.excluded {
        if archetype_has(arch, cid) {
            return false
        }
    }

    // Check wildcard pair terms
    for wt in ctx.wildcard_terms {
        matched := archetype_find_pair_with_relation(arch, wt.relation_cid) != 0
        if wt.negate {
            if matched do return false
        } else {
            if !matched do return false
        }
    }

    // Check any_of groups - at least one term in each group must match
    for &group in ctx.any_of_groups {
        if !archetype_matches_any_of(world, arch, group.terms) {
            return false
        }
    }

    return true
}

// Check if archetype matches at least one term in any_of group
archetype_matches_any_of :: proc(world: ^World, arch: ^Archetype, terms: []Term) -> bool {
    for &term in terms {
        if archetype_matches_term(world, arch, &term) {
            return true
        }
    }
    return false
}

// Check if archetype matches a single term
archetype_matches_term :: proc(world: ^World, arch: ^Archetype, term: ^Term) -> bool {
    match: bool

    switch term.kind {
    case .Component:
        cid := resolve_type(world, term.type_id)
        match = archetype_has(arch, cid)

    case .Pair:
        if is_wildcard_pair_term(term) {
            r_cid: ComponentID
            if term.relation == nil && term.relation_entity != 0 {
                r_cid = ComponentID(entity_index(term.relation_entity))
            } else {
                r_cid = resolve_type(world, term.relation)
            }
            match = archetype_find_pair_with_relation(arch, r_cid) != 0
        } else {
            pair_cid: ComponentID
            if term.relation == nil && term.relation_entity != 0 {
                pair_cid = resolve_pair_entity_relation(world, term.relation_entity, term.target)
            } else {
                pair_cid = resolve_pair(world, term.relation, term.target)
            }
            match = archetype_has(arch, pair_cid)
        }

    case .Group:
        switch term.group_op {
        case .All:
            for &t in term.group_terms {
                if !archetype_matches_term(world, arch, &t) {
                    return term.negate  // All must match, one failed
                }
            }
            match = true
        case .Any:
            match = archetype_matches_any_of(world, arch, term.group_terms)
        case .None:
            // None should match
            for &t in term.group_terms {
                if archetype_matches_term(world, arch, &t) {
                    return term.negate  // Found a match, fail
                }
            }
            match = true
        }
    }

    if term.negate {
        return !match
    }
    return match
}

// Process terms into Query_Context (new implementation with wildcards, any_of, captures)
process_terms_ctx :: proc(world: ^World, terms: []Term, ctx: ^Query_Context) {
    for &term in terms {
        process_term_ctx(world, &term, ctx)
    }
}

// Process a single term into Query_Context
process_term_ctx :: proc(world: ^World, term: ^Term, ctx: ^Query_Context) {
    // Track capture if specified
    if term.capture_to != None && term.capture_to != This && term.capture_to < MAX_QUERY_BINDINGS {
        if term.kind == .Pair && is_wildcard_pair_term(term) {
            r_cid: ComponentID
            if term.relation == nil && term.relation_entity != 0 {
                r_cid = ComponentID(entity_index(term.relation_entity))
            } else {
                r_cid = resolve_type(world, term.relation)
            }
            append(&ctx.captures, Capture_Info{
                relation_cid = r_cid,
                var_index    = u8(term.capture_to),
            })
        }
    }

    switch term.kind {
    case .Component:
        cid := resolve_type(world, term.type_id)
        if term.negate {
            append(&ctx.excluded, cid)
        } else {
            append(&ctx.required, cid)
        }

    case .Pair:
        // Check if this is a wildcard pair
        if is_wildcard_pair_term(term) {
            r_cid: ComponentID
            if term.relation == nil && term.relation_entity != 0 {
                r_cid = ComponentID(entity_index(term.relation_entity))
            } else {
                r_cid = resolve_type(world, term.relation)
            }
            append(&ctx.wildcard_terms, Wildcard_Term{
                relation_cid = r_cid,
                negate       = term.negate,
            })

            // Track cascade relation if this term has cascade enabled
            if term.cascade && ctx.cascade_rel == 0 {
                ctx.cascade_rel = r_cid
            }
        } else {
            // Exact pair match
            pair_cid: ComponentID
            if term.relation == nil && term.relation_entity != 0 {
                pair_cid = resolve_pair_entity_relation(world, term.relation_entity, term.target)
            } else {
                pair_cid = resolve_pair(world, term.relation, term.target)
            }
            // Ensure pair is registered
            if _, ok := world.component_info[pair_cid]; !ok {
                ti := type_info_of(term.relation)
                size := 0
                if ti != nil {
                    size = ti.size
                }
                ensure_pair_registered(world, pair_cid, size)
            }
            if term.negate {
                append(&ctx.excluded, pair_cid)
            } else {
                append(&ctx.required, pair_cid)
            }
        }

    case .Group:
        switch term.group_op {
        case .All:
            // All terms must match - process recursively
            process_terms_ctx(world, term.group_terms, ctx)
        case .Any:
            // At least one must match - store as any_of group
            append(&ctx.any_of_groups, Any_Of_Group{
                terms = term.group_terms,
            })
        case .None:
            // None should match - invert each term and add to excluded/wildcards
            for &t in term.group_terms {
                inverted := t
                inverted.negate = !inverted.negate
                process_term_ctx(world, &inverted, ctx)
            }
        }
    }
}

// Legacy: Process terms and collect required/excluded ComponentIDs (backward compat)
process_terms :: proc(world: ^World, terms: []Term, required: ^[dynamic]ComponentID, excluded: ^[dynamic]ComponentID) {
    for &term in terms {
        process_term(world, &term, required, excluded)
    }
}

// Legacy: Process a single term (takes pointer to avoid 80+ byte copy)
process_term :: proc(world: ^World, term: ^Term, required: ^[dynamic]ComponentID, excluded: ^[dynamic]ComponentID) {
    switch term.kind {
    case .Component:
        cid := resolve_type(world, term.type_id)
        if term.negate {
            append(excluded, cid)
        } else {
            append(required, cid)
        }
    case .Pair:
        pair_cid: ComponentID
        // Check if relation is an entity or a type
        if term.relation == nil && term.relation_entity != 0 {
            // Entity relation
            pair_cid = resolve_pair_entity_relation(world, term.relation_entity, term.target)
        } else {
            // Type relation
            pair_cid = resolve_pair(world, term.relation, term.target)
        }
        // Ensure pair is registered
        if _, ok := world.component_info[pair_cid]; !ok {
            // Get size from relation type (0 for tag pairs / entity relations)
            ti := type_info_of(term.relation)
            size := 0
            if ti != nil {
                size = ti.size
            }
            ensure_pair_registered(world, pair_cid, size)
        }
        if term.negate {
            append(excluded, pair_cid)
        } else {
            append(required, pair_cid)
        }
    case .Group:
        switch term.group_op {
        case .All:
            // All terms must match - add to same lists
            process_terms(world, term.group_terms, required, excluded)
        case .Any:
            // Legacy: treat as all (old behavior for backward compat via process_term)
            process_terms(world, term.group_terms, required, excluded)
        case .None:
            // None should match - invert and add to excluded
            for &t in term.group_terms {
                inverted := t
                inverted.negate = !inverted.negate
                process_term(world, &inverted, required, excluded)
            }
        }
    }
}

// =============================================================================
// QUERY ITERATOR
// =============================================================================
//
// IMPORTANT: Iterators enter "iteration mode" which defers structural changes
// (add/remove component, destroy entity) until iteration completes.
//
// The iterator automatically exits iteration mode when exhausted via query_next().
// However, if you break out of iteration early, you MUST call query_finish()
// to properly exit iteration mode and flush deferred operations.
//
// Example:
//   iter := query_iter(world, terms)
//   for entity, arch, row in query_next(&iter) {
//       if some_condition {
//           query_finish(&iter)  // REQUIRED when breaking early!
//           break
//       }
//   }
//   // If loop completes normally, query_finish is called automatically

Query_Iterator :: struct {
    world:          ^World,
    archetypes:     []^Archetype,
    arch_index:     int,
    entity_index:   int,
    finished:       bool,  // Track if we've already decremented depth

    // Variable binding support
    captures:       []Capture_Info,

    // Disabled component filtering
    flags:          Query_Flags,
    required_cids:  []ComponentID,  // For disabled check
}

query_iter :: proc(world: ^World, types: []typeid) -> Query_Iterator {
    return query_iter_with_flags(world, types, {})
}

query_iter_with_flags :: proc(world: ^World, types: []typeid, flags: Query_Flags) -> Query_Iterator {
    // Convert typeids to Terms
    terms := typeids_to_terms(types)

    // Build query context to get captures and required CIDs
    ctx := query_context_init()
    process_terms_ctx(world, terms, &ctx)

    // Flush only at outermost iteration level to prevent mid-iteration corruption
    if world.iteration_depth == 0 {
        flush_deferred(world)
    }

    // Check cache
    key := hash_query_context(&ctx)
    if cached, ok := &world.query_cache^[key]; ok {
        if cached.generation == world.archetype_generation {
            // Cache hit - use cached slices (already cloned with cache_allocator)
            world.iteration_depth += 1
            return Query_Iterator{
                world         = world,
                archetypes    = cached.archetypes[:],
                arch_index    = 0,
                entity_index  = 0,
                finished      = false,
                captures      = cached.captures,
                flags         = flags,
                required_cids = cached.required_cids,
            }
        }
        // Stale - clear old result and free old slices
        clear(&cached.archetypes)
        delete(cached.captures, world.cache_allocator)
        delete(cached.required_cids, world.cache_allocator)
        cached.captures = nil
        cached.required_cids = nil
    }

    // Cache miss or stale - scan archetypes
    if key not_in world.query_cache^ {
        world.query_cache^[key] = Cached_Query{
            archetypes = make([dynamic]^Archetype, world.cache_allocator),
            generation = 0,
        }
    }
    cached := &world.query_cache^[key]

    for arch in world.archetypes {
        if archetype_matches_query(world, arch, &ctx) {
            append(&cached.archetypes, arch)
        }
    }
    cached.generation = world.archetype_generation

    // Clone captures and required_cids with cache_allocator for cache persistence
    cached.captures = slice.clone(ctx.captures[:], world.cache_allocator)
    cached.required_cids = slice.clone(ctx.required[:], world.cache_allocator)

    world.iteration_depth += 1  // Enter iteration mode for deferred protection

    return Query_Iterator{
        world         = world,
        archetypes    = cached.archetypes[:],
        arch_index    = 0,
        entity_index  = 0,
        finished      = false,
        captures      = cached.captures,
        flags         = flags,
        required_cids = cached.required_cids,
    }
}

query_next :: proc(iter: ^Query_Iterator) -> (entity: EntityID, archetype: ^Archetype, row: int, ok: bool) {
    for iter.arch_index < len(iter.archetypes) {
        arch := iter.archetypes[iter.arch_index]

        for iter.entity_index < len(arch.entities) {
            entity = arch.entities[iter.entity_index]
            row = iter.entity_index
            iter.entity_index += 1

            // Check disabled components unless Include_Disabled flag is set
            if .Include_Disabled not_in iter.flags {
                if entity_has_disabled_required(iter.world, entity, iter.required_cids) {
                    continue  // Skip this entity
                }
            }

            archetype = arch
            ok = true
            return
        }
        iter.arch_index += 1
        iter.entity_index = 0
    }

    // Iterator exhausted - exit iteration mode and flush deferred ops
    if !iter.finished && iter.world != nil {
        iter.finished = true
        iter.world.iteration_depth = max(0, iter.world.iteration_depth - 1)
        if iter.world.iteration_depth == 0 {
            flush_deferred(iter.world)
        }
    }
    return
}

// Query iteration that returns Query_Result with variable bindings populated
query_next_result :: proc(iter: ^Query_Iterator) -> (result: Query_Result, ok: bool) {
    entity, arch, row, found := query_next(iter)
    if !found do return

    result.entity = entity
    result.archetype = arch
    result.row = row

    // Populate bindings from captures
    populate_query_bindings(arch, iter.captures, &result.bindings)

    return result, true
}

// Populate bindings from captured wildcard pairs
populate_query_bindings :: proc(arch: ^Archetype, captures: []Capture_Info, bindings: ^[8]EntityID) {
    for &info in captures {
        matched_cid := archetype_find_pair_with_relation(arch, info.relation_cid)
        if matched_cid != 0 {
            target_cid := pair_target(matched_cid)
            bindings[info.var_index] = EntityID(target_cid)
        }
    }
}

// Check if entity has any disabled required components
entity_has_disabled_required :: proc(world: ^World, entity: EntityID, required: []ComponentID) -> bool {
    disabled, ok := world.disabled_components[entity]
    if !ok do return false
    for cid in required {
        if cid in disabled do return true
    }
    return false
}

// Manually finish an iterator (call this if you break early from iteration)
query_finish :: proc(iter: ^Query_Iterator) {
    if !iter.finished && iter.world != nil {
        iter.finished = true
        iter.world.iteration_depth = max(0, iter.world.iteration_depth - 1)
        if iter.world.iteration_depth == 0 {
            flush_deferred(iter.world)
        }
    }
}

// Get component from archetype at row (for use in query iteration)
get_component_from_archetype :: proc(world: ^World, arch: ^Archetype, row: int, $T: typeid) -> ^T {
    cid, ok := get_component_id(world, T)
    if !ok do return nil

    col_idx := archetype_get_column(arch, cid)
    if col_idx < 0 do return nil

    return column_get(&arch.columns[col_idx], row, T)
}

// Get table/column slice from archetype (for batch processing)
get_table :: proc(world: ^World, arch: ^Archetype, $T: typeid) -> []T {
    cid, ok := get_component_id(world, T)
    if !ok do return nil

    col_idx := archetype_get_column(arch, cid)
    if col_idx < 0 do return nil

    col := &arch.columns[col_idx]
    when ODIN_DEBUG {
        assert(col.elem_size == size_of(T), "get_table: type size mismatch with column element size")
    }
    count := len(arch.entities)
    if count == 0 do return nil

    // Safety: ensure column data is sized correctly
    if len(col.data) < count * col.elem_size do return nil

    ptr := cast([^]T)&col.data[0]
    return ptr[:count]
}

// Get table and cast to a different type (CastTo must have same size as column element)
get_table_cast :: proc(world: ^World, arch: ^Archetype, $Component: typeid, $CastTo: typeid) -> []CastTo {
    cid, ok := get_component_id(world, Component)
    if !ok do return nil

    col_idx := archetype_get_column(arch, cid)
    if col_idx < 0 do return nil

    col := &arch.columns[col_idx]
    when ODIN_DEBUG {
        assert(col.elem_size == size_of(CastTo), "get_table_cast: CastTo size mismatch with column element size")
    }
    count := len(arch.entities)
    if count == 0 do return nil

    ptr := cast([^]CastTo)&col.data[0]
    return ptr[:count]
}

// Get table for a pair relationship
get_table_pair :: proc(world: ^World, arch: ^Archetype, $R, $T: typeid) -> []R {
    pair_cid := get_pair_id(world, R, T)

    col_idx := archetype_get_column(arch, pair_cid)
    if col_idx < 0 do return nil

    col := &arch.columns[col_idx]
    when ODIN_DEBUG {
        assert(col.elem_size == size_of(R), "get_table_pair: relation type size mismatch with column element size")
    }
    count := len(arch.entities)
    if count == 0 do return nil

    ptr := cast([^]R)&col.data[0]
    return ptr[:count]
}

// Get table for a pair with entity target
get_table_pair_entity :: proc(world: ^World, arch: ^Archetype, $R: typeid, target: EntityID) -> []R {
    pair_cid := get_pair_id_relation_entity(world, R, target)

    col_idx := archetype_get_column(arch, pair_cid)
    if col_idx < 0 do return nil

    col := &arch.columns[col_idx]
    when ODIN_DEBUG {
        assert(col.elem_size == size_of(R), "get_table_pair_entity: relation type size mismatch with column element size")
    }
    count := len(arch.entities)
    if count == 0 do return nil

    ptr := cast([^]R)&col.data[0]
    return ptr[:count]
}

get_entities :: proc(arch: ^Archetype) -> []EntityID {
    return arch.entities[:]
}
