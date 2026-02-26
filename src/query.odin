package ecs

import "core:slice"

// =============================================================================
// QUERY SYSTEM - DECLARATIVE API
// =============================================================================

// Pure term constructors - no world parameter needed
// Usage: query(world, {all(Position, Velocity), not(Dead)})
//        query(world, {Position, Velocity})  // shorthand for all()

// Term_Arg allows passing either a Term or a raw typeid to query()
// This enables: query(world, {Enemy}) as shorthand for query(world, {all(Enemy)})
Term_Arg :: union {
    Term,
    typeid,
}

// Convert Term_Arg to Term (typeids become simple "has component" terms)
term_arg_to_term :: proc(arg: Term_Arg) -> Term {
    switch a in arg {
    case Term:
        return a
    case typeid:
        return term_from_typeid(a)
    }
    return Term{}  // Should never reach here
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

pair_types :: proc($R, $T: typeid) -> Term {
    return Term{
        kind     = .Pair,
        relation = R,
        target   = Pair_Target(typeid_of(T)),
        source   = This,
        capture_to = None,
    }
}

pair_type_entity :: proc($R: typeid, target: EntityID) -> Term {
    return Term{
        kind     = .Pair,
        relation = R,
        target   = target,
        source   = This,
        capture_to = None,
    }
}

pair_entity_type :: proc(relation: EntityID, $T: typeid) -> Term {
    return Term{
        kind            = .Pair,
        relation        = nil,
        relation_entity = relation,
        target          = Pair_Target(typeid_of(T)),
        source          = This,
        capture_to      = None,
    }
}

pair_entities :: proc(relation: EntityID, target: EntityID) -> Term {
    return Term{
        kind            = .Pair,
        relation        = nil,
        relation_entity = relation,
        target          = target,
        source          = This,
        capture_to      = None,
    }
}

pair_wildcard :: proc($R: typeid, _: Wildcard_T) -> Term {
    return Term{
        kind     = .Pair,
        relation = R,
        target   = Wildcard,
        source   = This,
        capture_to = None,
    }
}

pair_any :: proc($R: typeid, _: Any_T) -> Term {
    return Term{
        kind     = .Pair,
        relation = R,
        target   = Any,
        source   = This,
        capture_to = None,
    }
}

pair_var :: proc($R: typeid, v: Var) -> Term {
    return Term{
        kind     = .Pair,
        relation = R,
        target   = v,
        source   = This,
        capture_to = None,
    }
}

// Term modifiers - return new Term with modification applied

on :: proc {
    on_term,
    on_typeid,
}

on_term :: proc(v: Var, t: Term) -> Term {
    r := t
    r.source = v
    return r
}

on_typeid :: proc(v: Var, T: typeid) -> Term {
    return on_term(v, term_from_typeid(T))
}

capture :: proc {
    capture_term,
    capture_typeid,
}

capture_term :: proc(v: Var, t: Term) -> Term {
    r := t
    r.capture_to = v
    return r
}

capture_typeid :: proc(v: Var, T: typeid) -> Term {
    return capture_term(v, term_from_typeid(T))
}

// Traversal modifiers - use up_with/down_with to specify relationship type
up :: proc {
    up_term,
    up_typeid,
}

up_term :: proc(t: Term) -> Term {
    r := t
    r.traverse_dir = .Up
    return r
}

up_typeid :: proc(T: typeid) -> Term {
    return up_term(term_from_typeid(T))
}

up_with :: proc {
    up_with_term,
    up_with_typeid,
}

up_with_term :: proc(t: Term, $R: typeid) -> Term {
    r := t
    r.traverse_dir = .Up
    r.traverse_rel = R
    return r
}

up_with_typeid :: proc(T: typeid, $R: typeid) -> Term {
    return up_with_term(term_from_typeid(T), R)
}

down :: proc {
    down_term,
    down_typeid,
}

down_term :: proc(t: Term) -> Term {
    r := t
    r.traverse_dir = .Down
    return r
}

down_typeid :: proc(T: typeid) -> Term {
    return down_term(term_from_typeid(T))
}

down_with :: proc {
    down_with_term,
    down_with_typeid,
}

down_with_term :: proc(t: Term, $R: typeid) -> Term {
    r := t
    r.traverse_dir = .Down
    r.traverse_rel = R
    return r
}

down_with_typeid :: proc(T: typeid, $R: typeid) -> Term {
    return down_with_term(term_from_typeid(T), R)
}

// =============================================================================
// GROUP CONSTRUCTORS: and/all, or/any, not/none
// =============================================================================
//
// NOTE: Group terms use temp_allocator for the nested term slice. This is
// intentional - Terms are designed for immediate use in queries, not long-term
// storage. The query system processes Terms and caches ComponentIDs, not Terms.

// AND - require all (aliases: and, all)
and_terms :: proc(terms: ..Term) -> Term {
    if len(terms) == 1 do return terms[0]
    return Term{
        kind        = .Group,
        group_op    = .All,
        group_terms = slice.clone(terms, context.temp_allocator),
        source      = This,
        capture_to  = None,
    }
}

and_typeids :: proc(types: ..typeid) -> Term {
    if len(types) == 1 {
        return term_from_typeid(types[0])
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = term_from_typeid(types[i])
    }
    return and_terms(..terms)
}

and :: proc {
    and_terms,
    and_typeids,
}

all :: proc {
    and_terms,
    and_typeids,
}

// OR - require any (aliases: or, any)
or_terms :: proc(terms: ..Term) -> Term {
    if len(terms) == 1 do return terms[0]
    return Term{
        kind        = .Group,
        group_op    = .Any,
        group_terms = slice.clone(terms, context.temp_allocator),
        source      = This,
        capture_to  = None,
    }
}

or_typeids :: proc(types: ..typeid) -> Term {
    if len(types) == 1 {
        return term_from_typeid(types[0])
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = term_from_typeid(types[i])
    }
    return or_terms(..terms)
}

or :: proc {
    or_terms,
    or_typeids,
}

some :: proc {
    or_terms,
    or_typeids,
}

// NOT/NONE - require none (aliases: not, none)
// Note: not() also works on single Term to negate it
none_terms :: proc(terms: ..Term) -> Term {
    if len(terms) == 1 {
        r := terms[0]
        r.negate = true
        return r
    }
    return Term{
        kind        = .Group,
        group_op    = .None,
        group_terms = slice.clone(terms, context.temp_allocator),
        source      = This,
        capture_to  = None,
    }
}

none_typeids :: proc(types: ..typeid) -> Term {
    if len(types) == 1 {
        t := term_from_typeid(types[0])
        t.negate = true
        return t
    }
    terms := make([]Term, len(types), context.temp_allocator)
    for i := 0; i < len(types); i += 1 {
        terms[i] = term_from_typeid(types[i])
    }
    return none_terms(..terms)
}

not :: proc {
    none_terms,
    none_typeids,
}

none :: proc {
    none_terms,
    none_typeids,
}

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
// ARCHETYPE ITERATOR - Safe iteration with automatic cleanup
// =============================================================================
//
// Usage:
//   q := ecs.query(world, {ecs.all(Position, Velocity)})
//   for arch in ecs.archs(&q) {
//       positions := ecs.get_table(world, arch, Position)
//       // ...
//   }
//   // Cleanup is automatic via @(deferred_out) - safe to break/return early
//
// For read-only iteration without structural changes, use query_raw() instead.

Query :: struct {
    world:      ^World,
    archetypes: []^Archetype,
    index:      int,
}

// Archetype iterator - use with: for arch in archs(&q)
archs :: proc(q: ^Query) -> (arch: ^Archetype, ok: bool) {
    if q.index >= len(q.archetypes) {
        return nil, false
    }
    arch = q.archetypes[q.index]
    q.index += 1
    return arch, true
}

// Automatic cleanup - called via @(deferred_out) when Query goes out of scope
query_auto_cleanup :: proc(q: Query) {
    if q.world != nil {
        q.world.iteration_depth -= 1
        if q.world.iteration_depth == 0 {
            flush_deferred(q.world)
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
query_raw :: proc(world: ^World, term_args: []Term_Arg) -> []^Archetype {
    return query_with_flags(world, term_args, {})
}

// Query with safe iteration - structural changes are deferred until query ends.
// Cleanup is automatic via @(deferred_out) when Query goes out of scope.
@(deferred_out=query_auto_cleanup)
query :: proc(world: ^World, term_args: []Term_Arg) -> Query {
    // Convert Term_Args to Terms
    terms := make([]Term, len(term_args), context.temp_allocator)
    for arg, i in term_args {
        terms[i] = term_arg_to_term(arg)
    }

    // Flush before entering iteration - only safe when not already iterating
    if world.iteration_depth == 0 {
        flush_deferred(world)
    }
    world.iteration_depth += 1
    return Query{
        world      = world,
        archetypes = query_with_flags_internal(world, terms, {}),
        index      = 0,
    }
}

// Query with optional flags (public API - accepts Term_Arg)
query_with_flags :: proc(world: ^World, term_args: []Term_Arg, flags: Query_Flags) -> []^Archetype {
    // Convert Term_Args to Terms
    terms := make([]Term, len(term_args), context.temp_allocator)
    for arg, i in term_args {
        terms[i] = term_arg_to_term(arg)
    }
    return query_with_flags_internal(world, terms, flags)
}

// Internal query implementation (works with []Term directly)
query_with_flags_internal :: proc(world: ^World, terms: []Term, flags: Query_Flags) -> []^Archetype {
    // Note: Flushing is handled by query() before incrementing iteration_depth
    // This prevents nested queries from flushing mid-iteration

    if len(terms) == 0 {
        return nil
    }

    // Build query context
    ctx := query_context_init()
    process_terms_ctx(world, terms, &ctx)

    // Check cache
    key := hash_query_context(&ctx)
    if cached, ok := &world.query_cache[key]; ok {
        if cached.generation == world.archetype_generation {
            return cached.archetypes[:]  // Cache hit
        }
        // Stale - clear old result and free old slices
        clear(&cached.archetypes)
        delete(cached.captures, world.allocator)
        delete(cached.required_cids, world.allocator)
        cached.captures = nil
        cached.required_cids = nil
    }

    // Cache miss or stale - scan archetypes
    if key not_in world.query_cache {
        world.query_cache[key] = Cached_Query{
            archetypes = make([dynamic]^Archetype, world.allocator),
            generation = 0,
        }
    }
    cached := &world.query_cache[key]

    for arch in world.archetypes {
        if archetype_matches_query(world, arch, &ctx) {
            append(&cached.archetypes, arch)
        }
    }
    cached.generation = world.archetype_generation

    // Clone captures and required_cids with world.allocator for cache persistence
    cached.captures = slice.clone(ctx.captures[:], world.allocator)
    cached.required_cids = slice.clone(ctx.required[:], world.allocator)

    return cached.archetypes[:]
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

query_iter :: proc(world: ^World, term_args: []Term_Arg) -> Query_Iterator {
    return query_iter_with_flags(world, term_args, {})
}

query_iter_with_flags :: proc(world: ^World, term_args: []Term_Arg, flags: Query_Flags) -> Query_Iterator {
    // Convert Term_Args to Terms
    terms := make([]Term, len(term_args), context.temp_allocator)
    for arg, i in term_args {
        terms[i] = term_arg_to_term(arg)
    }

    // Build query context to get captures and required CIDs
    ctx := query_context_init()
    process_terms_ctx(world, terms, &ctx)

    // Flush only at outermost iteration level to prevent mid-iteration corruption
    if world.iteration_depth == 0 {
        flush_deferred(world)
    }

    // Check cache
    key := hash_query_context(&ctx)
    if cached, ok := &world.query_cache[key]; ok {
        if cached.generation == world.archetype_generation {
            // Cache hit - use cached slices (already cloned with world.allocator)
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
        delete(cached.captures, world.allocator)
        delete(cached.required_cids, world.allocator)
        cached.captures = nil
        cached.required_cids = nil
    }

    // Cache miss or stale - scan archetypes
    if key not_in world.query_cache {
        world.query_cache[key] = Cached_Query{
            archetypes = make([dynamic]^Archetype, world.allocator),
            generation = 0,
        }
    }
    cached := &world.query_cache[key]

    for arch in world.archetypes {
        if archetype_matches_query(world, arch, &ctx) {
            append(&cached.archetypes, arch)
        }
    }
    cached.generation = world.archetype_generation

    // Clone captures and required_cids with world.allocator for cache persistence
    cached.captures = slice.clone(ctx.captures[:], world.allocator)
    cached.required_cids = slice.clone(ctx.required[:], world.allocator)

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
get_component_from_archetype :: proc(world: ^World, arch: ^Archetype, row: int, $T: typeid) -> (^T, bool) {
    cid, ok := get_component_id(world, T)
    if !ok do return nil, false

    col_idx := archetype_get_column(arch, cid)
    if col_idx < 0 do return nil, false

    ptr := column_get(&arch.columns[col_idx], row, T)
    return ptr, ptr != nil
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
