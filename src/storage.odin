package ecs

import "base:runtime"
import "core:mem"
import "core:slice"

// =============================================================================
// COMPONENT REGISTRY
// =============================================================================

Component_Info :: struct {
    size:      int,
    alignment: int,
    type_info: ^runtime.Type_Info,
}

// =============================================================================
// COLUMN STORAGE
// =============================================================================

Column :: struct {
    data:      [dynamic]byte,
    elem_size: int,
}

column_init :: proc(col: ^Column, elem_size: int, allocator: mem.Allocator) {
    col.elem_size = elem_size
    col.data = make([dynamic]byte, allocator)
}

column_destroy :: proc(col: ^Column) {
    delete(col.data)
}

column_grow :: proc(col: ^Column, count: int) {
    required := count * col.elem_size
    old_len := len(col.data)
    if old_len < required {
        resize(&col.data, required)
        // Zero-initialize new memory for safety
        mem.zero(&col.data[old_len], required - old_len)
    }
}

column_get :: #force_inline proc(col: ^Column, row: int, $T: typeid) -> ^T {
    if col.elem_size == 0 || row < 0 {
        return nil
    }
    when ODIN_DEBUG {
        assert(col.elem_size == size_of(T), "column_get: type size mismatch with column element size")
    }
    offset := row * col.elem_size
    if offset + col.elem_size > len(col.data) {
        return nil
    }
    return cast(^T)&col.data[offset]
}

column_set :: proc(col: ^Column, row: int, data: rawptr) {
    if col.elem_size == 0 {
        return
    }
    offset := row * col.elem_size
    column_grow(col, row + 1)
    mem.copy(&col.data[offset], data, col.elem_size)
}

column_copy_row :: proc(dst: ^Column, dst_row: int, src: ^Column, src_row: int) {
    if dst.elem_size == 0 || dst.elem_size != src.elem_size {
        return
    }
    // Bounds check source
    src_count := len(src.data) / src.elem_size
    assert(src_row >= 0 && src_row < src_count, "column_copy_row: src_row out of bounds")

    column_grow(dst, dst_row + 1)
    dst_offset := dst_row * dst.elem_size
    src_offset := src_row * src.elem_size
    mem.copy(&dst.data[dst_offset], &src.data[src_offset], dst.elem_size)
}

column_swap_remove :: proc(col: ^Column, row: int) {
    if col.elem_size == 0 {
        return
    }
    count := len(col.data) / col.elem_size
    // Bounds check
    assert(row >= 0 && row < count, "column_swap_remove: row out of bounds")
    assert(count > 0, "column_swap_remove: empty column")

    last_row := count - 1
    if row != last_row {
        dst_offset := row * col.elem_size
        src_offset := last_row * col.elem_size
        mem.copy(&col.data[dst_offset], &col.data[src_offset], col.elem_size)
    }
    new_size := last_row * col.elem_size
    assert(new_size >= 0, "column_swap_remove: negative size")
    resize(&col.data, new_size)
}

// =============================================================================
// ARCHETYPE
// =============================================================================

// Pre-computed edge for O(1) column mapping during entity moves
Archetype_Edge :: struct {
    target:     ^Archetype,
    column_map: []i16,  // len = target.columns, value = source col idx or -1 (new component)
}

Archetype :: struct {
    id:            ArchetypeID,
    signature:         []ComponentID,      // sorted signature (components + tags)
    columns:       []Column,           // columns for non-zero-size components
    column_indices: []i16,             // parallel to signature: column index or -1 for tags (cache-friendly)
    entities:      [dynamic]EntityID,

    // Transition cache with pre-computed column mappings
    add_edges:     map[ComponentID]Archetype_Edge,
    remove_edges:  map[ComponentID]Archetype_Edge,
}

archetype_init :: proc(arch: ^Archetype, world: ^World, sig: []ComponentID) {
    arch.signature = slice.clone(sig, world.allocator)
    arch.entities = make([dynamic]EntityID, world.allocator)
    arch.column_indices = make([]i16, len(sig), world.allocator)
    arch.add_edges = make(map[ComponentID]Archetype_Edge, allocator = world.allocator)
    arch.remove_edges = make(map[ComponentID]Archetype_Edge, allocator = world.allocator)

    // Count non-tag components for column allocation
    col_count := 0
    for cid in sig {
        info := world.component_info[cid]
        if info.size > 0 {
            col_count += 1
        }
    }

    arch.columns = make([]Column, col_count, world.allocator)
    col_idx: i16 = 0
    for i := 0; i < len(sig); i += 1 {
        cid := sig[i]
        info := world.component_info[cid]
        if info.size > 0 {
            column_init(&arch.columns[col_idx], info.size, world.allocator)
            arch.column_indices[i] = col_idx
            col_idx += 1
        } else {
            arch.column_indices[i] = -1  // Tag marker
        }
    }

    arch.id = hash_signature(sig)
}

// Compute column mapping from source to target archetype (called once when edge created)
compute_column_map :: proc(from: ^Archetype, to: ^Archetype, allocator: mem.Allocator) -> []i16 {
    col_map := make([]i16, len(to.columns), allocator)
    // Initialize to -1 (no source)
    for i in 0..<len(col_map) {
        col_map[i] = -1
    }
    // Map each target column to source column
    for to_type_idx := 0; to_type_idx < len(to.signature); to_type_idx += 1 {
        to_col := to.column_indices[to_type_idx]
        if to_col < 0 do continue  // Tag, no column
        cid := to.signature[to_type_idx]
        from_col := archetype_get_column(from, cid)
        if from_col >= 0 {
            col_map[to_col] = i16(from_col)
        }
    }
    return col_map
}

archetype_destroy :: proc(arch: ^Archetype, world: ^World) {
    // Free our column_maps and clean reverse edges in connected archetypes
    for cid, edge in arch.add_edges {
        delete(edge.column_map, world.allocator)
        // Our add edge's target should have a reverse remove edge pointing back
        if reverse, ok := edge.target.remove_edges[cid]; ok {
            delete(reverse.column_map, world.allocator)
            delete_key(&edge.target.remove_edges, cid)
        }
    }
    for cid, edge in arch.remove_edges {
        delete(edge.column_map, world.allocator)
        // Our remove edge's target should have a reverse add edge pointing back
        if reverse, ok := edge.target.add_edges[cid]; ok {
            delete(reverse.column_map, world.allocator)
            delete_key(&edge.target.add_edges, cid)
        }
    }

    for &col in arch.columns {
        column_destroy(&col)
    }
    delete(arch.columns, world.allocator)
    delete(arch.column_indices, world.allocator)
    delete(arch.signature, world.allocator)
    delete(arch.entities)
    delete(arch.add_edges)
    delete(arch.remove_edges)
}

// Remove archetype from world's dense array (swap-remove for O(1))
remove_archetype :: proc(world: ^World, arch: ^Archetype) {
    idx, ok := world.archetype_index[arch.id]
    if !ok do return

    last_idx := len(world.archetypes) - 1
    if idx != last_idx {
        // Swap with last
        last_arch := world.archetypes[last_idx]
        world.archetypes[idx] = last_arch
        world.archetype_index[last_arch.id] = idx
    }

    delete_key(&world.archetype_index, arch.id)
    pop(&world.archetypes)
    archetype_destroy(arch, world)
    free(arch, world.allocator)
    world.archetype_generation += 1  // Invalidate query cache
}

// Binary search on sorted signature array - cache-friendly O(log n)
archetype_find_component :: #force_inline proc(arch: ^Archetype, cid: ComponentID) -> (idx: int, found: bool) {
    lo, hi := 0, len(arch.signature) - 1
    for lo <= hi {
        mid := lo + (hi - lo) / 2
        mid_cid := arch.signature[mid]
        if mid_cid == cid {
            return mid, true
        } else if mid_cid < cid {
            lo = mid + 1
        } else {
            hi = mid - 1
        }
    }
    return -1, false
}

archetype_has :: #force_inline proc(arch: ^Archetype, cid: ComponentID) -> bool {
    _, found := archetype_find_component(arch, cid)
    return found
}

// Check if term has wildcard target
is_wildcard_pair_term :: proc(term: ^Term) -> bool {
    if term.kind != .Pair do return false
    #partial switch _ in term.target {
    case Wildcard_T, Any_T, Var:
        return true
    }
    return false
}

// Find first pair in archetype matching relation (0 if none)
// Pairs encode as: PAIR_FLAG | (relation << PAIR_TARGET_BITS) | target
archetype_find_pair_with_relation :: proc(arch: ^Archetype, relation_cid: ComponentID) -> ComponentID {
    lower := PAIR_FLAG | ((relation_cid & PAIR_RELATION_MAX) << PAIR_TARGET_BITS)
    upper := lower | PAIR_TARGET_MAX

    for cid in arch.signature {
        if cid >= lower && cid <= upper {
            return cid
        }
        if cid > upper do break  // Sorted, no more matches
    }
    return 0
}

// Find all pairs in archetype matching relation
// NOTE: Returns owned [dynamic]ComponentID - caller must delete() when done
archetype_find_all_pairs_with_relation :: proc(
    arch: ^Archetype,
    relation_cid: ComponentID,
    allocator: mem.Allocator,
) -> [dynamic]ComponentID {
    lower := PAIR_FLAG | ((relation_cid & PAIR_RELATION_MAX) << PAIR_TARGET_BITS)
    upper := lower | PAIR_TARGET_MAX

    result := make([dynamic]ComponentID, allocator)
    for cid in arch.signature {
        if cid >= lower && cid <= upper {
            append(&result, cid)
        } else if cid > upper {
            break
        }
    }
    return result
}

// Get column index for a component (-1 for tags, -2 if not found)
archetype_get_column :: #force_inline proc(arch: ^Archetype, cid: ComponentID) -> int {
    idx, found := archetype_find_component(arch, cid)
    if !found do return -2
    return int(arch.column_indices[idx])
}

archetype_add_entity :: proc(arch: ^Archetype, entity: EntityID) -> int {
    row := len(arch.entities)
    append(&arch.entities, entity)
    // Grow all columns
    for &col in arch.columns {
        column_grow(&col, row + 1)
    }
    return row
}

archetype_remove_entity :: proc(arch: ^Archetype, row: int) -> (moved_entity: EntityID, had_move: bool) {
    // Bounds check
    if row < 0 || row >= len(arch.entities) {
        return {}, false  // Invalid row, bail out
    }

    last := len(arch.entities) - 1
    if row != last {
        moved_entity = arch.entities[last]
        arch.entities[row] = moved_entity
        had_move = true
        // Swap-remove in all columns
        for &col in arch.columns {
            column_swap_remove(&col, row)
        }
    } else {
        // Just shrink
        for &col in arch.columns {
            resize(&col.data, row * col.elem_size)
        }
    }
    pop(&arch.entities)
    return
}

// =============================================================================
// SIGNATURE UTILITIES
// =============================================================================

hash_signature :: proc(sig: []ComponentID) -> ArchetypeID {
    h := u64(0xcbf29ce484222325)  // FNV-1a offset
    for cid in sig {
        h = (h ~ u64(cid)) * 0x100000001b3
    }
    return ArchetypeID(h)
}

sort_signature :: proc(sig: []ComponentID) {
    // Insertion sort (signatures are usually small)
    for i := 1; i < len(sig); i += 1 {
        key := sig[i]
        j := i - 1
        for j >= 0 && sig[j] > key {
            sig[j + 1] = sig[j]
            j -= 1
        }
        sig[j + 1] = key
    }
}
