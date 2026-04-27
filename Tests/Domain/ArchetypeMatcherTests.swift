import Testing
import Foundation
@testable import MTGCardScanner

@Suite("ArchetypeMatcher Tests")
struct ArchetypeMatcherTests {

    // MARK: - Similarity Calculation

    @Test("Perfect match returns similarity 1.0")
    func perfectMatch() {
        // Find any archetype and supply exactly its mainboard
        guard let archetype = ClassicArchetypes.all.first else { return }
        var deckCards: [String] = []
        for (name, qty) in archetype.mainboard {
            for _ in 0..<qty {
                deckCards.append(name)
            }
        }
        let match = ArchetypeMatcher.bestMatch(for: deckCards, minThreshold: 0.0)
        #expect(match != nil)
        #expect(match!.similarity >= 0.99)
    }

    @Test("Empty deck returns nil")
    func emptyDeck() {
        let match = ArchetypeMatcher.bestMatch(for: [], minThreshold: 0.0)
        #expect(match == nil)
    }

    @Test("Completely unrelated deck returns nil at default threshold")
    func unrelatedDeck() {
        let deckCards = Array(repeating: "Totally Made Up Card Name XYZ", count: 60)
        let match = ArchetypeMatcher.bestMatch(for: deckCards, minThreshold: 0.5)
        #expect(match == nil)
    }

    @Test("Missing cards are computed correctly")
    func missingCardsComputed() {
        guard let archetype = ClassicArchetypes.all.first else { return }
        // Supply half the cards
        var deckCards: [String] = []
        var count = 0
        for (name, qty) in archetype.mainboard {
            if count > archetype.mainboard.count / 2 { break }
            for _ in 0..<qty {
                deckCards.append(name)
            }
            count += 1
        }
        let match = ArchetypeMatcher.bestMatch(for: deckCards, minThreshold: 0.0)
        if let match {
            // Missing should contain cards not in our deck
            let missingTotal = match.missing.reduce(0) { $0 + $1.quantity }
            #expect(missingTotal > 0)
        }
    }

    @Test("Missing cards sorted by quantity descending")
    func missingSortedDescending() {
        guard let archetype = ClassicArchetypes.all.first else { return }
        // Supply no cards to get all missing
        let match = ArchetypeMatcher.bestMatch(for: ["Lightning Bolt"], minThreshold: 0.0)
        if let match {
            for i in 0..<(match.missing.count - 1) {
                #expect(match.missing[i].quantity >= match.missing[i + 1].quantity)
            }
        }
    }

    @Test("Case insensitive matching")
    func caseInsensitive() {
        guard let archetype = ClassicArchetypes.all.first else { return }
        var deckCards: [String] = []
        for (name, qty) in archetype.mainboard {
            for _ in 0..<qty {
                deckCards.append(name.uppercased())
            }
        }
        let match = ArchetypeMatcher.bestMatch(for: deckCards, minThreshold: 0.0)
        #expect(match != nil)
        #expect(match!.similarity >= 0.99)
    }

    @Test("Threshold filtering works")
    func thresholdFiltering() {
        guard let archetype = ClassicArchetypes.all.first else { return }
        // Supply just 1 card — similarity will be very low
        let firstCard = archetype.mainboard.keys.first ?? "Lightning Bolt"
        let match = ArchetypeMatcher.bestMatch(for: [firstCard], minThreshold: 0.9)
        #expect(match == nil)
    }

    @Test("similarityPercent rounds correctly")
    func similarityPercentRounding() {
        let match = ArchetypeMatch(
            archetype: ClassicArchetypes.all.first!,
            similarity: 0.756,
            missing: []
        )
        #expect(match.similarityPercent == 76)
    }
}
