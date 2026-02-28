package tests

import "core:testing"
import "core:fmt"
import ecs "../src"

// =============================================================================
// TEST TYPES - RPG-style relationships
// =============================================================================

// Tag components
Village :: distinct struct {}
City :: distinct struct {}
Vendor :: distinct struct {}
Blacksmith :: distinct struct {}
Alchemist :: distinct struct {}
Player :: distinct struct {}
NPC :: distinct struct {}

// Data components
Name :: struct {
    value: string,
}

// Position, Velocity, Health are defined in test.odin (same package)


// Relationship types (zero-sized for tag relationships)
LocatedIn :: distinct struct {}
ChildOf :: distinct struct {}
Likes :: distinct struct {}
Hates :: distinct struct {}

// Relationship type with data
Owns :: struct {
    share_percentage: int,
}

// Relationship with data
Sells :: struct {
    price:    int,
    quantity: int,
}

Distance :: struct {
    value: f32,
}

// Item types (as tag entities)
Potions :: distinct struct {}
Weapons :: distinct struct {}
Armor :: distinct struct {}
Food :: distinct struct {}

// Region types
Skyrim :: distinct struct {}
Cyrodiil :: distinct struct {}
Morrowind :: distinct struct {}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

count_query_results :: proc(world: ^ecs.World, types: []typeid) -> int {
    count := 0
    for arch in ecs.query(world, types) {
        count += len(ecs.get_entities(arch))
    }
    return count
}

// =============================================================================
// BASIC DECLARATIVE QUERY TESTS
// =============================================================================

@(test)
test_simple_has :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create some villages and cities
    v1 := ecs.add_entity(world)
    ecs.add_component(world, v1, Village{})
    ecs.add_component(world, v1, Name{"Riverwood"})

    v2 := ecs.add_entity(world)
    ecs.add_component(world, v2, Village{})
    ecs.add_component(world, v2, Name{"Whiterun"})

    c1 := ecs.add_entity(world)
    ecs.add_component(world, c1, City{})
    ecs.add_component(world, c1, Name{"Solitude"})

    // Query: Find all villages
    count := count_query_results(world, {ecs.all(Village)})
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 villages, got %d", count))

    // Query: Find all cities
    count = count_query_results(world, {ecs.all(City)})
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 city, got %d", count))

    // Query: Find all named entities
    count = count_query_results(world, {ecs.all(Name)})
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 named entities, got %d", count))
}

@(test)
test_vendor_queries :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Vendor who is also an alchemist
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Vendor{})
    ecs.add_component(world, e1, Alchemist{})
    ecs.add_component(world, e1, Name{"Arcadia"})

    // Vendor who is a blacksmith
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Vendor{})
    ecs.add_component(world, e2, Blacksmith{})
    ecs.add_component(world, e2, Name{"Eorlund"})

    // Just an alchemist (not a vendor)
    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Alchemist{})
    ecs.add_component(world, e3, Name{"Nurelion"})

    // Query: Vendor AND Alchemist
    count := count_query_results(world, {ecs.all(Vendor), ecs.all(Alchemist)})
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor-alchemist, got %d", count))

    // Query: Vendor AND Blacksmith
    count = count_query_results(world, {ecs.all(Vendor), ecs.all(Blacksmith)})
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor-blacksmith, got %d", count))

    // Query: All vendors
    count = count_query_results(world, {ecs.all(Vendor)})
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 vendors, got %d", count))

    // Query: All alchemists
    count = count_query_results(world, {ecs.all(Alchemist)})
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 alchemists, got %d", count))
}

@(test)
test_not_modifier :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Living NPC
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, NPC{})
    ecs.add_component(world, e1, Health{100})

    // Dead NPC (has a "Dead" marker we'll simulate with zero health check later)
    // For now, let's use a Dead tag
    Dead :: distinct struct {}

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, NPC{})
    ecs.add_component(world, e2, Health{0})
    ecs.add_component(world, e2, Dead{})

    // Another living NPC
    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, NPC{})
    ecs.add_component(world, e3, Health{50})

    // Query: NPCs that are NOT dead
    count := count_query_results(world, {ecs.all(NPC), ecs.not(ecs.all(Dead))})
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 living NPCs, got %d", count))

    // Query: NPCs that ARE dead
    count = count_query_results(world, {ecs.all(NPC), ecs.all(Dead)})
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 dead NPC, got %d", count))
}

// =============================================================================
// PAIR/RELATIONSHIP QUERY TESTS
// =============================================================================

@(test)
test_unified_pair_api :: proc(t: ^testing.T) {
    // This test demonstrates the unified pair() API:
    // - add_component(world, entity, pair(R, target)) works
    // - add_pair(world, entity, R, target) also works
    // - query(world, {has(X), pair(R, target)}) works

    world := ecs.create_world()
    defer ecs.delete_world(world)

    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    // Both APIs work for adding pairs:
    riverwood := ecs.add_entity(world)
    ecs.add_component(world, riverwood, Village{})
    ecs.add_component(world, riverwood, ecs.pair(LocatedIn, skyrim))  // NEW: pair() in add_component

    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, Village{})
    ecs.add_pair(world, whiterun, LocatedIn, skyrim)  // Traditional add_pair still works

    // Query using pair() - same function works in queries
    count := count_query_results(world, {
        ecs.all(Village),
        ecs.pair(LocatedIn, skyrim),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 villages in Skyrim, got %d", count))
}

@(test)
test_located_in_relationship :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create regions
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Skyrim{})
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    cyrodiil := ecs.add_entity(world)
    ecs.add_component(world, cyrodiil, Cyrodiil{})
    ecs.add_component(world, cyrodiil, Name{"Cyrodiil"})

    // Create villages in Skyrim
    riverwood := ecs.add_entity(world)
    ecs.add_component(world, riverwood, Village{})
    ecs.add_component(world, riverwood, Name{"Riverwood"})
    ecs.add_pair(world, riverwood, LocatedIn, skyrim)

    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, Village{})
    ecs.add_component(world, whiterun, Name{"Whiterun"})
    ecs.add_pair(world, whiterun, LocatedIn, skyrim)

    // Create a village in Cyrodiil
    chorrol := ecs.add_entity(world)
    ecs.add_component(world, chorrol, Village{})
    ecs.add_component(world, chorrol, Name{"Chorrol"})
    ecs.add_pair(world, chorrol, LocatedIn, cyrodiil)

    // Query: Villages in Skyrim
    // Village($v), LocatedIn($v, skyrim)
    count := count_query_results(world, {
        ecs.all(Village),
        ecs.pair(LocatedIn, skyrim),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 villages in Skyrim, got %d", count))

    // Query: Villages in Cyrodiil
    count = count_query_results(world, {
        ecs.all(Village),
        ecs.pair(LocatedIn, cyrodiil),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 village in Cyrodiil, got %d", count))

    // Query: All entities located in Skyrim
    count = count_query_results(world, {
        ecs.pair(LocatedIn, skyrim),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 entities in Skyrim, got %d", count))
}

@(test)
test_sells_relationship_with_data :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create item type entities
    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    // Create vendors
    arcadia := ecs.add_entity(world)
    ecs.add_component(world, arcadia, Vendor{})
    ecs.add_component(world, arcadia, Alchemist{})
    ecs.add_component(world, arcadia, Name{"Arcadia"})
    ecs.add_pair(world, arcadia, Sells{price = 50, quantity = 10}, potions)

    eorlund := ecs.add_entity(world)
    ecs.add_component(world, eorlund, Vendor{})
    ecs.add_component(world, eorlund, Blacksmith{})
    ecs.add_component(world, eorlund, Name{"Eorlund"})
    ecs.add_pair(world, eorlund, Sells{price = 500, quantity = 5}, weapons)

    belethor := ecs.add_entity(world)
    ecs.add_component(world, belethor, Vendor{})
    ecs.add_component(world, belethor, Name{"Belethor"})
    ecs.add_pair(world, belethor, Sells{price = 75, quantity = 3}, potions)
    ecs.add_pair(world, belethor, Sells{price = 300, quantity = 2}, weapons)

    // Query: Vendors that sell potions
    // Vendor($v), Sells($v, potions)
    count := count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Sells, potions),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 vendors selling potions, got %d", count))

    // Query: Vendors that sell weapons
    count = count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Sells, weapons),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 vendors selling weapons, got %d", count))

    // Query: Alchemist vendors that sell potions
    count = count_query_results(world, {
        ecs.all(Vendor),
        ecs.all(Alchemist),
        ecs.pair(Sells, potions),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 alchemist vendor selling potions, got %d", count))

    // Verify we can read the Sells data
    for arch in ecs.query(world, {ecs.all(Vendor), ecs.pair(Sells, potions)}) {
        sells_data := ecs.get_table_pair_entity(world, arch, Sells, potions)
        for s in sells_data {
            testing.expect(t, s.price > 0, "Sells price should be positive")
            testing.expect(t, s.quantity > 0, "Sells quantity should be positive")
        }
    }
}

@(test)
test_child_of_hierarchy :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create a hierarchy: Region > City > District > Building
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, City{})
    ecs.add_component(world, whiterun, Name{"Whiterun"})
    ecs.add_pair(world, whiterun, ChildOf, skyrim)

    plains_district := ecs.add_entity(world)
    ecs.add_component(world, plains_district, Name{"Plains District"})
    ecs.add_pair(world, plains_district, ChildOf, whiterun)

    cloud_district := ecs.add_entity(world)
    ecs.add_component(world, cloud_district, Name{"Cloud District"})
    ecs.add_pair(world, cloud_district, ChildOf, whiterun)

    dragonsreach := ecs.add_entity(world)
    ecs.add_component(world, dragonsreach, Name{"Dragonsreach"})
    ecs.add_pair(world, dragonsreach, ChildOf, cloud_district)

    // Query: Direct children of Whiterun
    count := count_query_results(world, {
        ecs.pair(ChildOf, whiterun),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 direct children of Whiterun, got %d", count))

    // Query: Direct children of Cloud District
    count = count_query_results(world, {
        ecs.pair(ChildOf, cloud_district),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 child of Cloud District, got %d", count))

    // Query: Direct children of Skyrim
    count = count_query_results(world, {
        ecs.pair(ChildOf, skyrim),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 direct child of Skyrim, got %d", count))
}

// =============================================================================
// NEGATION WITH PAIRS
// =============================================================================

@(test)
test_not_with_pairs :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    // Vendor that sells potions only
    v1 := ecs.add_entity(world)
    ecs.add_component(world, v1, Vendor{})
    ecs.add_component(world, v1, Name{"Potion Seller"})
    ecs.add_pair(world, v1, Sells{50, 10}, potions)

    // Vendor that sells weapons only
    v2 := ecs.add_entity(world)
    ecs.add_component(world, v2, Vendor{})
    ecs.add_component(world, v2, Name{"Weapon Seller"})
    ecs.add_pair(world, v2, Sells{500, 5}, weapons)

    // Vendor that sells both
    v3 := ecs.add_entity(world)
    ecs.add_component(world, v3, Vendor{})
    ecs.add_component(world, v3, Name{"General Goods"})
    ecs.add_pair(world, v3, Sells{75, 3}, potions)
    ecs.add_pair(world, v3, Sells{300, 2}, weapons)

    // Query: Vendors that DON'T sell potions
    // Vendor($v), !Sells($v, potions)
    count := count_query_results(world, {
        ecs.all(Vendor),
        ecs.not(ecs.pair(Sells, potions)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor not selling potions, got %d", count))

    // Query: Vendors that sell potions but NOT weapons
    count = count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Sells, potions),
        ecs.not(ecs.pair(Sells, weapons)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor selling potions but not weapons, got %d", count))

    // Query: Vendors that sell weapons but NOT potions
    count = count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Sells, weapons),
        ecs.not(ecs.pair(Sells, potions)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor selling weapons but not potions, got %d", count))
}

// =============================================================================
// COMPLEX SCENARIO: VILLAGES WITHOUT POTION VENDORS
// =============================================================================

// This test simulates the query:
// Village($village), LocatedIn($village, Skyrim), !{
//   LocatedIn($vendor, $village),
//   Vendor($vendor),
//   Sells($vendor, Potions)
// }
//
// Current limitation: We don't have full variable binding across terms,
// so we simulate this with a manual approach.

@(test)
test_villages_without_potion_vendors :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create regions
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Skyrim{})

    // Create item type
    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    // Village 1: Riverwood - has a potion vendor
    riverwood := ecs.add_entity(world)
    ecs.add_component(world, riverwood, Village{})
    ecs.add_component(world, riverwood, Name{"Riverwood"})
    ecs.add_pair(world, riverwood, LocatedIn, skyrim)

    lucan := ecs.add_entity(world)
    ecs.add_component(world, lucan, Vendor{})
    ecs.add_component(world, lucan, Name{"Lucan Valerius"})
    ecs.add_pair(world, lucan, LocatedIn, riverwood)
    ecs.add_pair(world, lucan, Sells{50, 5}, potions)

    // Village 2: Rorikstead - has a vendor but NOT selling potions
    rorikstead := ecs.add_entity(world)
    ecs.add_component(world, rorikstead, Village{})
    ecs.add_component(world, rorikstead, Name{"Rorikstead"})
    ecs.add_pair(world, rorikstead, LocatedIn, skyrim)

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    ennis := ecs.add_entity(world)
    ecs.add_component(world, ennis, Vendor{})
    ecs.add_component(world, ennis, Name{"Ennis"})
    ecs.add_pair(world, ennis, LocatedIn, rorikstead)
    ecs.add_pair(world, ennis, Sells{100, 3}, weapons)

    // Village 3: Ivarstead - has no vendor at all
    ivarstead := ecs.add_entity(world)
    ecs.add_component(world, ivarstead, Village{})
    ecs.add_component(world, ivarstead, Name{"Ivarstead"})
    ecs.add_pair(world, ivarstead, LocatedIn, skyrim)

    // Query all villages in Skyrim
    villages_in_skyrim := count_query_results(world, {
        ecs.all(Village),
        ecs.pair(LocatedIn, skyrim),
    })
    testing.expect(t, villages_in_skyrim == 3,
        fmt.tprintf("Expected 3 villages in Skyrim, got %d", villages_in_skyrim))

    // Manual query: Find villages in Skyrim that DON'T have a potion vendor
    // (This is how you'd do it without full variable binding)
    villages_without_potion_vendor := 0

    for arch in ecs.query(world, {ecs.all(Village), ecs.pair(LocatedIn, skyrim)}) {
        villages := ecs.get_entities(arch)
        for village in villages {
            // Check if any vendor in this village sells potions
            has_potion_vendor := false

            for vendor_arch in ecs.query(world, {
                ecs.all(Vendor),
                ecs.pair(LocatedIn, village),
                ecs.pair(Sells, potions),
            }) {
                if len(ecs.get_entities(vendor_arch)) > 0 {
                    has_potion_vendor = true
                    break  // Cleanup automatic via @(deferred_out)
                }
            }

            if !has_potion_vendor {
                villages_without_potion_vendor += 1
            }
        }
    }

    // Rorikstead (vendor sells weapons, not potions) and Ivarstead (no vendor)
    testing.expect(t, villages_without_potion_vendor == 2,
        fmt.tprintf("Expected 2 villages without potion vendors, got %d", villages_without_potion_vendor))
}

// =============================================================================
// GROUP OPERATORS
// =============================================================================

@(test)
test_all_group :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Entity with all components
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Vendor{})
    ecs.add_component(world, e1, Alchemist{})
    ecs.add_component(world, e1, Name{"Full"})

    // Entity missing one
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Vendor{})
    ecs.add_component(world, e2, Name{"Partial"})

    // Using all() group - should find entities with ALL specified components
    count := count_query_results(world, {
        ecs.all(ecs.all(Vendor), ecs.all(Alchemist), ecs.all(Name)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 entity with all components, got %d", count))
}

@(test)
test_none_of_group :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    Dead :: distinct struct {}
    Hostile :: distinct struct {}

    // Friendly living NPC
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, NPC{})
    ecs.add_component(world, e1, Name{"Friendly"})

    // Dead NPC
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, NPC{})
    ecs.add_component(world, e2, Name{"Dead One"})
    ecs.add_component(world, e2, Dead{})

    // Hostile NPC
    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, NPC{})
    ecs.add_component(world, e3, Name{"Hostile One"})
    ecs.add_component(world, e3, Hostile{})

    // Dead AND Hostile NPC
    e4 := ecs.add_entity(world)
    ecs.add_component(world, e4, NPC{})
    ecs.add_component(world, e4, Name{"Dead Hostile"})
    ecs.add_component(world, e4, Dead{})
    ecs.add_component(world, e4, Hostile{})

    // Query: NPCs that are neither Dead nor Hostile
    // NPC, !Dead, !Hostile
    count := count_query_results(world, {
        ecs.all(NPC),
        ecs.not(ecs.all(Dead)),
        ecs.not(ecs.all(Hostile)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 friendly living NPC, got %d", count))

    // Same query using none_of group
    count = count_query_results(world, {
        ecs.all(NPC),
        ecs.none(ecs.all(Dead), ecs.all(Hostile)),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 friendly living NPC (using none_of), got %d", count))
}

// =============================================================================
// ENTITY-ENTITY RELATIONSHIPS
// =============================================================================

@(test)
test_entity_entity_relationships :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create some characters
    player := ecs.add_entity(world)
    ecs.add_component(world, player, Player{})
    ecs.add_component(world, player, Name{"Dragonborn"})

    lydia := ecs.add_entity(world)
    ecs.add_component(world, lydia, NPC{})
    ecs.add_component(world, lydia, Name{"Lydia"})

    nazeem := ecs.add_entity(world)
    ecs.add_component(world, nazeem, NPC{})
    ecs.add_component(world, nazeem, Name{"Nazeem"})

    // Create a custom relationship entity
    likes_relation := ecs.add_entity(world)
    hates_relation := ecs.add_entity(world)

    // Set up relationships (use explicit proc for entity-entity pairs)
    ecs.add_pair_entities(world, lydia, likes_relation, player)  // Lydia likes Player
    ecs.add_pair_entities(world, player, hates_relation, nazeem) // Player hates Nazeem
    ecs.add_pair_entities(world, nazeem, likes_relation, nazeem) // Nazeem likes himself

    // Query: Who likes the player?
    count := count_query_results(world, {
        ecs.pair(likes_relation, player),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 entity liking player, got %d", count))

    // Query: Who does the player hate?
    // We need to check player's hates relationships
    testing.expect(t, ecs.has_pair(world, player, hates_relation, nazeem),
        "Player should hate Nazeem")

    // Query: NPCs that like themselves (narcissists)
    narcissists := 0
    for arch in ecs.query(world, {ecs.all(NPC)}) {
        for npc in ecs.get_entities(arch) {
            if ecs.has_pair(world, npc, likes_relation, npc) {
                narcissists += 1
            }
        }
    }
    testing.expect(t, narcissists == 1, fmt.tprintf("Expected 1 narcissist, got %d", narcissists))
}

// =============================================================================
// MULTIPLE PAIR TYPES ON SAME ENTITY
// =============================================================================

@(test)
test_multiple_relationship_types :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create locations
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, City{})
    ecs.add_component(world, whiterun, Name{"Whiterun"})
    ecs.add_pair(world, whiterun, LocatedIn, skyrim)

    // Create items
    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    // Create a vendor with multiple relationships
    belethor := ecs.add_entity(world)
    ecs.add_component(world, belethor, Vendor{})
    ecs.add_component(world, belethor, Name{"Belethor"})
    ecs.add_pair(world, belethor, LocatedIn, whiterun)            // Location
    ecs.add_pair(world, belethor, Sells{50, 5}, potions)  // Sells potions
    ecs.add_pair(world, belethor, Sells{200, 3}, weapons) // Sells weapons
    ecs.add_pair(world, belethor, Owns{100}, whiterun)     // Owns shop in Whiterun (100%)

    // Query: Vendors in Whiterun that sell potions
    count := count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(LocatedIn, whiterun),
        ecs.pair(Sells, potions),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor in Whiterun selling potions, got %d", count))

    // Query: Vendors that own something in Whiterun
    count = count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Owns, whiterun),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 vendor owning in Whiterun, got %d", count))

    // Query: Entities in Whiterun (should include both the city's children and the vendor)
    count = count_query_results(world, {
        ecs.pair(LocatedIn, whiterun),
    })
    testing.expect(t, count == 1, fmt.tprintf("Expected 1 entity located in Whiterun, got %d", count))
}

// =============================================================================
// WILDCARD PAIR MATCHING TESTS
// =============================================================================

@(test)
test_wildcard_pair_matching :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create parent entities
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    cyrodiil := ecs.add_entity(world)
    ecs.add_component(world, cyrodiil, Name{"Cyrodiil"})

    // Create children
    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, City{})
    ecs.add_component(world, whiterun, Name{"Whiterun"})
    ecs.add_pair(world, whiterun, ChildOf, skyrim)

    solitude := ecs.add_entity(world)
    ecs.add_component(world, solitude, City{})
    ecs.add_component(world, solitude, Name{"Solitude"})
    ecs.add_pair(world, solitude, ChildOf, skyrim)

    imperial_city := ecs.add_entity(world)
    ecs.add_component(world, imperial_city, City{})
    ecs.add_component(world, imperial_city, Name{"Imperial City"})
    ecs.add_pair(world, imperial_city, ChildOf, cyrodiil)

    // Entity without ChildOf relationship
    standalone := ecs.add_entity(world)
    ecs.add_component(world, standalone, Village{})
    ecs.add_component(world, standalone, Name{"Standalone"})

    // Query: Find all entities with ChildOf(*) - any parent
    count := count_query_results(world, {
        ecs.pair(ChildOf, ecs.Wildcard),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 entities with ChildOf relationship, got %d", count))

    // Query: Cities with any ChildOf relationship
    count = count_query_results(world, {
        ecs.all(City),
        ecs.pair(ChildOf, ecs.Wildcard),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 cities with parents, got %d", count))

    // Query: Entities WITHOUT any ChildOf relationship
    count = count_query_results(world, {
        ecs.all(Name),
        ecs.not(ecs.pair(ChildOf, ecs.Wildcard)),
    })
    // skyrim, cyrodiil, and standalone don't have ChildOf
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 entities without ChildOf, got %d", count))
}

@(test)
test_wildcard_with_sells_relationship :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create item types
    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    food := ecs.add_entity(world)
    ecs.add_component(world, food, Food{})

    // Create vendors
    alchemist := ecs.add_entity(world)
    ecs.add_component(world, alchemist, Vendor{})
    ecs.add_component(world, alchemist, Name{"Alchemist"})
    ecs.add_pair(world, alchemist, Sells{50, 10}, potions)

    blacksmith := ecs.add_entity(world)
    ecs.add_component(world, blacksmith, Vendor{})
    ecs.add_component(world, blacksmith, Name{"Blacksmith"})
    ecs.add_pair(world, blacksmith, Sells{200, 5}, weapons)

    general_goods := ecs.add_entity(world)
    ecs.add_component(world, general_goods, Vendor{})
    ecs.add_component(world, general_goods, Name{"General Goods"})
    ecs.add_pair(world, general_goods, Sells{75, 3}, potions)
    ecs.add_pair(world, general_goods, Sells{150, 2}, weapons)
    ecs.add_pair(world, general_goods, Sells{10, 20}, food)

    // Non-vendor (doesn't sell anything)
    npc := ecs.add_entity(world)
    ecs.add_component(world, npc, NPC{})
    ecs.add_component(world, npc, Name{"Regular NPC"})

    // Query: Vendors that sell ANYTHING (Sells, *)
    count := count_query_results(world, {
        ecs.all(Vendor),
        ecs.pair(Sells, ecs.Wildcard),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 vendors that sell something, got %d", count))

    // Query: All entities with any Sells relationship
    count = count_query_results(world, {
        ecs.pair(Sells, ecs.Wildcard),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 entities that sell something, got %d", count))
}

// =============================================================================
// VARIABLE BINDING / CAPTURE TESTS
// =============================================================================

@(test)
test_variable_capture :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create parent entities
    skyrim := ecs.add_entity(world)
    ecs.add_component(world, skyrim, Name{"Skyrim"})

    cyrodiil := ecs.add_entity(world)
    ecs.add_component(world, cyrodiil, Name{"Cyrodiil"})

    // Create children in Skyrim
    whiterun := ecs.add_entity(world)
    ecs.add_component(world, whiterun, City{})
    ecs.add_component(world, whiterun, Name{"Whiterun"})
    ecs.add_pair(world, whiterun, ChildOf, skyrim)

    // Create child in Cyrodiil
    imperial_city := ecs.add_entity(world)
    ecs.add_component(world, imperial_city, City{})
    ecs.add_component(world, imperial_city, Name{"Imperial City"})
    ecs.add_pair(world, imperial_city, ChildOf, cyrodiil)

    // Use capture to bind the wildcard target to a variable
    v0 : ecs.Var : 0

    iter := ecs.query_iter(world, {
        ecs.all(City),
        ecs.capture(v0, ecs.pair(ChildOf, ecs.Wildcard)),
    })
    defer ecs.query_finish(&iter)

    found_parents := make(map[ecs.EntityID]int, allocator = context.temp_allocator)

    for result in ecs.query_next_result(&iter) {
        parent := result.bindings[0]
        found_parents[parent] = found_parents[parent] + 1
    }

    // Should find skyrim once (whiterun's parent) and cyrodiil once (imperial_city's parent)
    testing.expect(t, len(found_parents) == 2, fmt.tprintf("Expected 2 unique parents, got %d", len(found_parents)))

    // The captured values should be valid entity IDs (converted from ComponentID)
    for parent_id, count in found_parents {
        testing.expect(t, count == 1, fmt.tprintf("Each parent should appear once, got %d", count))
        testing.expect(t, parent_id != 0, "Parent ID should not be zero")
    }
}

// =============================================================================
// ANY_OF GROUP TESTS
// =============================================================================

@(test)
test_any_of_group :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Entity with only Position
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Position{1, 1})
    ecs.add_component(world, e1, Name{"Position Only"})

    // Entity with only Velocity
    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Velocity{2, 2})
    ecs.add_component(world, e2, Name{"Velocity Only"})

    // Entity with both
    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Position{3, 3})
    ecs.add_component(world, e3, Velocity{3, 3})
    ecs.add_component(world, e3, Name{"Both"})

    // Entity with neither (just Health)
    e4 := ecs.add_entity(world)
    ecs.add_component(world, e4, Health{100})
    ecs.add_component(world, e4, Name{"Neither"})

    // Query: Entities with Position OR Velocity
    count := count_query_results(world, {
        ecs.or(ecs.all(Position), ecs.all(Velocity)),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 entities with Position or Velocity, got %d", count))

    // Query: Named entities with Position OR Velocity
    count = count_query_results(world, {
        ecs.all(Name),
        ecs.or(ecs.all(Position), ecs.all(Velocity)),
    })
    testing.expect(t, count == 3, fmt.tprintf("Expected 3 named entities with Position or Velocity, got %d", count))
}

@(test)
test_any_of_with_pairs :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create targets
    potions := ecs.add_entity(world)
    ecs.add_component(world, potions, Potions{})

    weapons := ecs.add_entity(world)
    ecs.add_component(world, weapons, Weapons{})

    armor := ecs.add_entity(world)
    ecs.add_component(world, armor, Armor{})

    // Vendor selling potions
    v1 := ecs.add_entity(world)
    ecs.add_component(world, v1, Vendor{})
    ecs.add_component(world, v1, Name{"Potion Seller"})
    ecs.add_pair(world, v1, Sells{50, 10}, potions)

    // Vendor selling weapons
    v2 := ecs.add_entity(world)
    ecs.add_component(world, v2, Vendor{})
    ecs.add_component(world, v2, Name{"Weapon Seller"})
    ecs.add_pair(world, v2, Sells{200, 5}, weapons)

    // Vendor selling armor (neither potions nor weapons)
    v3 := ecs.add_entity(world)
    ecs.add_component(world, v3, Vendor{})
    ecs.add_component(world, v3, Name{"Armor Seller"})
    ecs.add_pair(world, v3, Sells{300, 3}, armor)

    // Query: Vendors selling potions OR weapons
    count := count_query_results(world, {
        ecs.all(Vendor),
        ecs.or(ecs.pair(Sells, potions), ecs.pair(Sells, weapons)),
    })
    testing.expect(t, count == 2, fmt.tprintf("Expected 2 vendors selling potions or weapons, got %d", count))
}

// =============================================================================
// DISABLED COMPONENT FILTERING TESTS
// =============================================================================

@(test)
test_disabled_filtering_via_iterator :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create entities with Health
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Health{100})
    ecs.add_component(world, e1, Name{"Healthy"})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Health{50})
    ecs.add_component(world, e2, Name{"Injured"})

    e3 := ecs.add_entity(world)
    ecs.add_component(world, e3, Health{0})
    ecs.add_component(world, e3, Name{"Dead"})

    // Disable Health on e3
    ecs.disable_component(world, e3, Health)
    testing.expect(t, ecs.is_component_disabled(world, e3, Health), "Health should be disabled on e3")

    // query() returns archetypes - doesn't filter at entity level
    archetype_count := count_query_results(world, {ecs.all(Health)})
    testing.expect(t, archetype_count == 3, fmt.tprintf("query() should still see 3 entities, got %d", archetype_count))

    // query_iter without Include_Disabled flag should skip disabled entities
    iter := ecs.query_iter(world, {ecs.all(Health)})
    defer ecs.query_finish(&iter)

    count := 0
    for _ in ecs.query_next(&iter) {
        count += 1
    }
    testing.expect(t, count == 2, fmt.tprintf("Iterator should see 2 entities (skipping disabled), got %d", count))
}

@(test)
test_include_disabled_flag :: proc(t: ^testing.T) {
    world := ecs.create_world()
    defer ecs.delete_world(world)

    // Create entities
    e1 := ecs.add_entity(world)
    ecs.add_component(world, e1, Health{100})

    e2 := ecs.add_entity(world)
    ecs.add_component(world, e2, Health{50})

    // Disable Health on e2
    ecs.disable_component(world, e2, Health)

    // With Include_Disabled flag, should see all entities
    iter := ecs.query_iter_with_flags(world, {ecs.all(Health)}, {.Include_Disabled})
    defer ecs.query_finish(&iter)

    count := 0
    for _ in ecs.query_next(&iter) {
        count += 1
    }
    testing.expect(t, count == 2, fmt.tprintf("Iterator with Include_Disabled should see 2 entities, got %d", count))
}
