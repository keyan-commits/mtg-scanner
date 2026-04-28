import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Gemini batch response parser")
struct GeminiBatchResponseParserTests {

    // MARK: - Per-photo shape (preferred)

    @Test("Parses per-photo shape with multiple cards in one photo")
    func perPhotoShape() {
        let text = """
        [
          {"image_index": 0, "cards": [
            {"card_name": "Lightning Bolt", "set_code": "lea", "collector_number": "161", "quantity": 1},
            {"card_name": "Counterspell",   "set_code": "lea", "collector_number": "55",  "quantity": 1}
          ]},
          {"image_index": 1, "cards": [
            {"card_name": "Skirk Prospector", "set_code": "ons", "collector_number": "230", "quantity": 4}
          ]}
        ]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 3)
        #expect(results[0].cardName == "Lightning Bolt")
        #expect(results[0].imageIndex == 0)
        #expect(results[0].quantity == 1)
        #expect(results[1].cardName == "Counterspell")
        #expect(results[1].imageIndex == 0)
        #expect(results[2].cardName == "Skirk Prospector")
        #expect(results[2].imageIndex == 1)
        #expect(results[2].quantity == 4)
        #expect(results[2].setCode == "ons")
        #expect(results[2].collectorNumber == "230")
    }

    @Test("Empty cards array for a photo emits no entries for that photo")
    func emptyCardsArray() {
        let text = """
        [
          {"image_index": 0, "cards": []},
          {"image_index": 1, "cards": [{"card_name": "Black Lotus", "set_code": "lea", "collector_number": "232"}]}
        ]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].imageIndex == 1)
        #expect(results[0].cardName == "Black Lotus")
    }

    @Test("Missing image_index falls back to positional order")
    func missingImageIndex() {
        let text = """
        [
          {"cards": [{"card_name": "Card A"}]},
          {"cards": [{"card_name": "Card B"}]}
        ]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 2)
        #expect(results[0].imageIndex == 0)
        #expect(results[1].imageIndex == 1)
    }

    @Test("Quantity defaults to 1 when missing")
    func quantityDefault() {
        let text = """
        [{"image_index": 0, "cards": [{"card_name": "Test Card"}]}]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].quantity == 1)
    }

    @Test("Quantity floor of 1 when Gemini returns 0 or negative")
    func quantityFloor() {
        let text = """
        [{"image_index": 0, "cards": [
            {"card_name": "Zero Qty", "quantity": 0},
            {"card_name": "Neg Qty",  "quantity": -3}
        ]}]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 2)
        #expect(results[0].quantity == 1)
        #expect(results[1].quantity == 1)
    }

    // MARK: - Wrapped object shapes

    @Test("Parses wrapped object under \"results\" key")
    func wrappedResults() {
        let text = """
        {"results": [
          {"image_index": 0, "cards": [{"card_name": "Wrapped Card"}]}
        ]}
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].cardName == "Wrapped Card")
    }

    @Test("Parses wrapped object under \"cards\" key")
    func wrappedCardsKey() {
        let text = """
        {"cards": [{"image_index": 0, "cards": [{"card_name": "Nested Card"}]}]}
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].cardName == "Nested Card")
    }

    // MARK: - Legacy flat shape

    @Test("Parses legacy flat array shape")
    func legacyFlat() {
        let text = """
        [
          {"index": 0, "card_name": "Old Card A", "set_code": "lea", "collector_number": "1"},
          {"index": 1, "card_name": "Old Card B", "set_code": null,  "collector_number": null}
        ]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 2)
        #expect(results[0].imageIndex == 0)
        #expect(results[0].cardName == "Old Card A")
        #expect(results[0].setCode == "lea")
        #expect(results[1].imageIndex == 1)
        #expect(results[1].setCode == nil)
        #expect(results[1].collectorNumber == nil)
    }

    @Test("Legacy flat array without index falls back to positional")
    func legacyFlatPositional() {
        let text = """
        [
          {"card_name": "First"},
          {"card_name": "Second"}
        ]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 2)
        #expect(results[0].imageIndex == 0)
        #expect(results[1].imageIndex == 1)
    }

    // MARK: - Tolerance & error paths

    @Test("Strips markdown code fences")
    func stripsMarkdown() {
        let text = """
        ```json
        [{"image_index": 0, "cards": [{"card_name": "Fenced Card"}]}]
        ```
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].cardName == "Fenced Card")
    }

    @Test("Malformed JSON returns empty array")
    func malformedJSON() {
        let results = GeminiVisionService.parseBatchResponse(text: "this is not JSON at all")
        #expect(results.isEmpty)
    }

    @Test("Empty string returns empty array")
    func emptyString() {
        #expect(GeminiVisionService.parseBatchResponse(text: "").isEmpty)
    }

    @Test("Empty array returns empty results")
    func emptyArray() {
        #expect(GeminiVisionService.parseBatchResponse(text: "[]").isEmpty)
    }

    @Test("Items missing card_name are skipped, not fatal")
    func skipsMissingCardName() {
        let text = """
        [{"image_index": 0, "cards": [
            {"set_code": "lea"},
            {"card_name": "Valid Card"},
            {"card_name": ""}
        ]}]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].cardName == "Valid Card")
    }

    @Test("Tolerates \"name\" field as alias for card_name")
    func nameAlias() {
        let text = """
        [{"image_index": 0, "cards": [{"name": "Alias Card"}]}]
        """
        let results = GeminiVisionService.parseBatchResponse(text: text)
        #expect(results.count == 1)
        #expect(results[0].cardName == "Alias Card")
    }
}
