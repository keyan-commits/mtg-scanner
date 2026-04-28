import Testing
import CoreGraphics
@testable import MTGCardScanner

@Suite("CardRectangleSelector")
struct CardRectangleSelectorTests {

    private func rect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    @Test("Empty input returns nil")
    func emptyReturnsNil() {
        #expect(CardRectangleSelector.pickBest(boundingBoxes: []) == nil)
    }

    @Test("Single rectangle is picked through")
    func singleRectanglePicked() {
        let r = rect(width: 0.4, height: 0.55)
        #expect(CardRectangleSelector.pickBest(boundingBoxes: [r]) == r)
    }

    @Test("When card and stand both present, the smaller one wins")
    func smallerCardWinsOverContainer() {
        // The user's scanner stand: a tallish container that the Vision
        // request already lets through (its true aspect is in 0.55–0.85). The
        // card sitting inside it is also a valid rectangle, just smaller.
        let standInterior = rect(width: 0.85, height: 1.10)  // big, ratio ≈ 0.77
        let card = rect(width: 0.45, height: 0.62)            // small, ratio ≈ 0.73
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [standInterior, card])
        #expect(picked == card)
    }

    @Test("Three rectangles — smallest wins regardless of order")
    func smallestOfThreeWins() {
        let big = rect(width: 0.9, height: 1.2)
        let medium = rect(width: 0.6, height: 0.8)
        let tiny = rect(width: 0.3, height: 0.4)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [big, medium, tiny])
        #expect(picked == tiny)
    }

    @Test("Two equally-sized rectangles — either is a valid pick")
    func tiesAreStable() {
        let a = rect(width: 0.4, height: 0.55)
        let b = rect(width: 0.4, height: 0.55)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [a, b])
        #expect(picked == a || picked == b)
    }

    @Test("Tilted card whose AABB is squarish is still acceptable")
    func tiltedAABBSurvives() {
        // Perspective tilt inflates the AABB so the card's axis-aligned aspect
        // can drift well outside the canonical 0.714. The selector must not
        // reject these — Vision already filtered by true aspect upstream.
        let tiltedCard = rect(width: 0.5, height: 0.55)  // ratio ≈ 0.91
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [tiltedCard])
        #expect(picked == tiltedCard)
    }
}
