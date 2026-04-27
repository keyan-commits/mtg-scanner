import Testing
import Foundation
@testable import MTGCardScanner

@Suite("CardCategory Tests")
struct CardCategoryTests {

    @Test("Creature type line maps to .creatures")
    func creature() {
        #expect(CardCategory.from(typeLine: "Creature — Human Wizard") == .creatures)
    }

    @Test("Legendary Creature maps to .creatures")
    func legendaryCreature() {
        #expect(CardCategory.from(typeLine: "Legendary Creature — Dragon") == .creatures)
    }

    @Test("Artifact Creature maps to .creatures (creature wins)")
    func artifactCreature() {
        #expect(CardCategory.from(typeLine: "Artifact Creature — Golem") == .creatures)
    }

    @Test("Enchantment Creature maps to .creatures (creature wins)")
    func enchantmentCreature() {
        #expect(CardCategory.from(typeLine: "Enchantment Creature — God") == .creatures)
    }

    @Test("Planeswalker maps to .planeswalkers")
    func planeswalker() {
        #expect(CardCategory.from(typeLine: "Legendary Planeswalker — Jace") == .planeswalkers)
    }

    @Test("Instant maps to .instants")
    func instant() {
        #expect(CardCategory.from(typeLine: "Instant") == .instants)
    }

    @Test("Sorcery maps to .sorceries")
    func sorcery() {
        #expect(CardCategory.from(typeLine: "Sorcery") == .sorceries)
    }

    @Test("Artifact maps to .artifacts")
    func artifact() {
        #expect(CardCategory.from(typeLine: "Artifact") == .artifacts)
    }

    @Test("Enchantment maps to .enchantments")
    func enchantment() {
        #expect(CardCategory.from(typeLine: "Enchantment — Aura") == .enchantments)
    }

    @Test("Land maps to .lands")
    func land() {
        #expect(CardCategory.from(typeLine: "Land") == .lands)
    }

    @Test("Basic Land maps to .lands")
    func basicLand() {
        #expect(CardCategory.from(typeLine: "Basic Land — Island") == .lands)
    }

    @Test("Nil typeLine maps to .other")
    func nilTypeLine() {
        #expect(CardCategory.from(typeLine: nil) == .other)
    }

    @Test("Unknown type maps to .other")
    func unknownType() {
        #expect(CardCategory.from(typeLine: "Conspiracy") == .other)
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        #expect(CardCategory.from(typeLine: "CREATURE — ELF") == .creatures)
    }

    @Test("Sort order: creatures before lands")
    func sortOrder() {
        #expect(CardCategory.creatures.sortOrder < CardCategory.lands.sortOrder)
    }

    @Test("Sort order: commander is first")
    func commanderFirst() {
        #expect(CardCategory.commander.sortOrder == 0)
    }
}
