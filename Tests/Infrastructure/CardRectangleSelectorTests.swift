import Testing
import CoreGraphics
@testable import MTGCardScanner

@Suite("CardRectangleSelector")
struct CardRectangleSelectorTests {

    // Standard Magic card aspect: 2.5" / 3.5" = 0.714.
    private let cardAspect: CGFloat = 0.714

    private func rect(width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: width, height: height)
    }

    @Test("Empty input returns nil")
    func emptyReturnsNil() {
        #expect(CardRectangleSelector.pickBest(boundingBoxes: []) == nil)
    }

    @Test("Single card-aspect rectangle is picked")
    func singleCardAspectPicked() {
        let card = rect(width: 0.4, height: 0.4 / cardAspect)
        #expect(CardRectangleSelector.pickBest(boundingBoxes: [card]) == card)
    }

    @Test("When card and stand both present, smaller card-aspect rectangle wins")
    func smallerCardWinsOverContainer() {
        // The user's scanner stand: a tallish near-card-aspect container that
        // happens to fall inside the request's loose 0.55-0.85 range. The card
        // sitting inside it is also card-aspect but smaller.
        let standInterior = rect(width: 0.85, height: 0.85 / cardAspect)  // big
        let card = rect(width: 0.45, height: 0.45 / cardAspect)            // small
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [standInterior, card])
        #expect(picked == card)
    }

    @Test("Squarish container rectangles are filtered out by aspect")
    func squarishFilteredOut() {
        let squareIsh = rect(width: 0.7, height: 0.75)  // ratio ≈ 0.93 — outside range
        let card = rect(width: 0.4, height: 0.4 / cardAspect)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [squareIsh, card])
        #expect(picked == card)
    }

    @Test("Too-narrow rectangles are filtered out")
    func tooNarrowFiltered() {
        let narrow = rect(width: 0.3, height: 0.7)  // ratio ≈ 0.43 — outside range
        let card = rect(width: 0.4, height: 0.4 / cardAspect)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [narrow, card])
        #expect(picked == card)
    }

    @Test("All non-card-aspect input returns nil")
    func allRejectedReturnsNil() {
        let square = rect(width: 0.5, height: 0.5)
        let landscape = rect(width: 0.7, height: 0.4)
        #expect(CardRectangleSelector.pickBest(boundingBoxes: [square, landscape]) == nil)
    }

    @Test("Two equally-sized card-aspect rectangles — either is a valid pick")
    func tiesAreStable() {
        let a = rect(width: 0.4, height: 0.4 / cardAspect)
        let b = rect(width: 0.4, height: 0.4 / cardAspect)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [a, b])
        #expect(picked == a || picked == b)
    }

    @Test("Zero-height rectangle is rejected (no divide by zero)")
    func zeroHeightRejected() {
        let degenerate = rect(width: 0.5, height: 0)
        let card = rect(width: 0.4, height: 0.4 / cardAspect)
        let picked = CardRectangleSelector.pickBest(boundingBoxes: [degenerate, card])
        #expect(picked == card)
    }

    @Test("isCardAspect rejects ratios just outside the band")
    func boundaryAspectsRejected() {
        // Ratio 0.64 — just below the 0.65 floor.
        let belowFloor = rect(width: 0.64, height: 1.0)
        // Ratio 0.81 — just above the 0.80 ceiling.
        let aboveCeiling = rect(width: 0.81, height: 1.0)
        #expect(CardRectangleSelector.isCardAspect(belowFloor) == false)
        #expect(CardRectangleSelector.isCardAspect(aboveCeiling) == false)
    }

    @Test("isCardAspect accepts the exact MTG card ratio")
    func cardAspectAccepted() {
        let card = rect(width: 0.714, height: 1.0)
        #expect(CardRectangleSelector.isCardAspect(card) == true)
    }
}
