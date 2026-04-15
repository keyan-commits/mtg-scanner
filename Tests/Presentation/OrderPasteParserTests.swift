import XCTest
@testable import MTGCardScanner

final class OrderPasteParserTests: XCTestCase {

    // MARK: - Real-world Hareruya paste

    /// Exact format the user receives from their Hareruya middleman.
    private let hareruyaPaste = """
    Confirmed Mar-25 Hareruya order

    Total due = 11650 <PAID as of Mar-25>

    ETA April 17, 2026

    Details:

        <White>
    2    Swords to Plowshares [4ED] = 450ea
    4    Armageddon [4ED] = 720ea
    1    Land Tax [4ED] = 1720ea
    4    Kjeldoran Outpost [ALL] = 740ea
    1    Strip Mine <1> [4ED] = 990ea

        <Black>
    4    Dark Ritual [ICE] = 250ea
    4    Hypnotic Specter [4ED] = 300ea
    """

    func testHareruyaPasteParsesAllCardLines() {
        let lines = OrderPasteParser.parse(hareruyaPaste)
        XCTAssertEqual(lines.count, 7, "Should parse exactly 7 card lines (skipping headers, totals, color sections)")
    }

    func testHareruyaPasteParsesQuantitiesNamesAndPrices() {
        let lines = OrderPasteParser.parse(hareruyaPaste)
        let expected: [OrderPasteParser.ParsedLine] = [
            .init(quantity: 2, name: "Swords to Plowshares", setCode: "4ed", variant: nil, pricePerCard: 450),
            .init(quantity: 4, name: "Armageddon", setCode: "4ed", variant: nil, pricePerCard: 720),
            .init(quantity: 1, name: "Land Tax", setCode: "4ed", variant: nil, pricePerCard: 1720),
            .init(quantity: 4, name: "Kjeldoran Outpost", setCode: "all", variant: nil, pricePerCard: 740),
            .init(quantity: 1, name: "Strip Mine", setCode: "4ed", variant: "1", pricePerCard: 990),
            .init(quantity: 4, name: "Dark Ritual", setCode: "ice", variant: nil, pricePerCard: 250),
            .init(quantity: 4, name: "Hypnotic Specter", setCode: "4ed", variant: nil, pricePerCard: 300),
        ]
        XCTAssertEqual(lines, expected)
    }

    func testHareruyaPasteTotalCardCount() {
        let lines = OrderPasteParser.parse(hareruyaPaste)
        let totalCards = lines.reduce(0) { $0 + $1.quantity }
        XCTAssertEqual(totalCards, 20, "Total ordered: 2+4+1+4+1+4+4 = 20")
    }

    func testHareruyaPasteTotalPriceMatches() {
        let lines = OrderPasteParser.parse(hareruyaPaste)
        // Per-card prices × quantities — should match the seller's "Total due = 11650"
        let computed = lines.reduce(0.0) { acc, l in acc + (l.pricePerCard ?? 0) * Double(l.quantity) }
        XCTAssertEqual(computed, 11650, "Sum of qty * pricePerCard should equal the seller's 'Total due'")
    }

    // MARK: - shouldSkip

    func testShouldSkipHeaders() {
        XCTAssertTrue(OrderPasteParser.shouldSkip("Total due = 11650"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("Confirmed Mar-25 Hareruya order"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("Details:"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("ETA April 17, 2026"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("Shipping = 500"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("Subtotal: 11150"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("Tax 5%"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("// comment"))
    }

    func testShouldSkipColorSectionMarkers() {
        XCTAssertTrue(OrderPasteParser.shouldSkip("<White>"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("<Black>"))
        XCTAssertTrue(OrderPasteParser.shouldSkip("<Red>"))
    }

    func testShouldNotSkipCardLines() {
        XCTAssertFalse(OrderPasteParser.shouldSkip("2    Swords to Plowshares [4ED] = 450ea"))
        XCTAssertFalse(OrderPasteParser.shouldSkip("1    Strip Mine <1> [4ED] = 990ea"))
    }

    // MARK: - parseLine edge cases

    func testParseLineWithoutEa() {
        let line = OrderPasteParser.parseLine("4 Lightning Bolt [M11] = 0.50")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: "m11", variant: nil, pricePerCard: 0.50))
    }

    func testParseLineWithoutPrice() {
        let line = OrderPasteParser.parseLine("4 Lightning Bolt [M11]")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: "m11", variant: nil, pricePerCard: nil))
    }

    func testParseLineWithoutSet() {
        let line = OrderPasteParser.parseLine("4 Lightning Bolt = 0.50")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: nil, variant: nil, pricePerCard: 0.50))
    }

    func testParseLineWithVariant() {
        let line = OrderPasteParser.parseLine("1 Strip Mine <1> [4ED] = 990ea")
        XCTAssertEqual(line, .init(quantity: 1, name: "Strip Mine", setCode: "4ed", variant: "1", pricePerCard: 990))
    }

    func testParseLineWithCommaDecimal() {
        let line = OrderPasteParser.parseLine("4 Lightning Bolt [M11] = 0,50ea")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: "m11", variant: nil, pricePerCard: 0.50))
    }

    func testParseLineWithXMultiplier() {
        let line = OrderPasteParser.parseLine("4x Lightning Bolt [M11] = 0.50")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: "m11", variant: nil, pricePerCard: 0.50))
    }

    func testParseLineRejectsNonNumericStart() {
        XCTAssertNil(OrderPasteParser.parseLine("Lightning Bolt"))
        XCTAssertNil(OrderPasteParser.parseLine(""))
    }

    // MARK: - Trailing metadata after the price (regression: real Card Kingdom paste)

    func testParseLineWithTrailingNoteAfterPrice() {
        let line = OrderPasteParser.parseLine("4 Contagion [ALL] = 150ea, Card Kingdom")
        XCTAssertEqual(line, .init(quantity: 4, name: "Contagion", setCode: "all", variant: nil, pricePerCard: 150))
    }

    func testParseLineWithLongTrailingNote() {
        let line = OrderPasteParser.parseLine("2 Serrated Arrows [HML] = 40ea, Card Kingdom, Order of Leitbur was ignored")
        XCTAssertEqual(line, .init(quantity: 2, name: "Serrated Arrows", setCode: "hml", variant: nil, pricePerCard: 40))
    }

    func testParseLineWithoutEaButWithTrailingNote() {
        let line = OrderPasteParser.parseLine("4 Lightning Bolt [M11] = 0.50, eBay seller")
        XCTAssertEqual(line, .init(quantity: 4, name: "Lightning Bolt", setCode: "m11", variant: nil, pricePerCard: 0.50))
    }
}
