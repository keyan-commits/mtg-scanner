import Testing
import Foundation
@testable import MTGCardScanner

@Suite("Gemini batch response parser")
struct GeminiBatchResponseParserTests {

    // MARK: - Wrapped object shape (preferred)

    @Test("Parses preferred wrapped shape with analysis + per-photo cards + bboxes")
    func wrappedWithAnalysisAndBboxes() {
        let text = """
        {
          "analysis": "Three pages from a vintage Onslaught/Urza's Saga collection.",
          "results": [
            {"image_index": 0, "cards": [
              {"card_name": "Lightning Bolt", "set_code": "lea", "collector_number": "161", "quantity": 1, "x": 0.05, "y": 0.10, "w": 0.40, "h": 0.45},
              {"card_name": "Counterspell",   "set_code": "lea", "collector_number": "55",  "quantity": 1, "x": 0.55, "y": 0.10, "w": 0.40, "h": 0.45}
            ]},
            {"image_index": 1, "cards": [
              {"card_name": "Skirk Prospector", "set_code": "ons", "collector_number": "230", "quantity": 4}
            ]}
          ]
        }
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.analysis?.contains("Onslaught") == true)
        #expect(parsed.cards.count == 3)
        #expect(parsed.cards[0].cardName == "Lightning Bolt")
        #expect(parsed.cards[0].imageIndex == 0)
        #expect(parsed.cards[0].boundingBox?.x == 0.05)
        #expect(parsed.cards[0].boundingBox?.w == 0.40)
        #expect(parsed.cards[1].cardName == "Counterspell")
        #expect(parsed.cards[2].cardName == "Skirk Prospector")
        #expect(parsed.cards[2].quantity == 4)
        #expect(parsed.cards[2].boundingBox == nil)
    }

    @Test("Empty analysis string is normalized to nil")
    func emptyAnalysisIsNil() {
        let text = """
        {"analysis": "  ", "results": [{"image_index": 0, "cards": [{"card_name": "Test"}]}]}
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.analysis == nil)
        #expect(parsed.cards.count == 1)
    }

    @Test("Bounding box with zero width/height is dropped")
    func degenerateBboxRejected() {
        let text = """
        {"results": [{"image_index": 0, "cards": [
            {"card_name": "X", "x": 0.1, "y": 0.1, "w": 0.0, "h": 0.5},
            {"card_name": "Y", "x": 0.1, "y": 0.1, "w": 0.5, "h": -0.1}
        ]}]}
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].boundingBox == nil)
        #expect(parsed.cards[1].boundingBox == nil)
    }

    // MARK: - Per-photo array shape (no analysis)

    @Test("Parses bare per-photo array")
    func perPhotoArray() {
        let text = """
        [
          {"image_index": 0, "cards": [{"card_name": "Card A"}]},
          {"image_index": 1, "cards": []}
        ]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.analysis == nil)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].imageIndex == 0)
    }

    @Test("Missing image_index falls back to positional order")
    func missingImageIndex() {
        let text = """
        [
          {"cards": [{"card_name": "Card A"}]},
          {"cards": [{"card_name": "Card B"}]}
        ]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].imageIndex == 0)
        #expect(parsed.cards[1].imageIndex == 1)
    }

    // MARK: - Quantity handling

    @Test("Quantity defaults to 1 when missing")
    func quantityDefault() {
        let text = """
        [{"image_index": 0, "cards": [{"card_name": "Test Card"}]}]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].quantity == 1)
    }

    @Test("Quantity floor of 1 for zero or negative input")
    func quantityFloor() {
        let text = """
        [{"image_index": 0, "cards": [
            {"card_name": "Zero Qty", "quantity": 0},
            {"card_name": "Neg Qty",  "quantity": -3}
        ]}]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].quantity == 1)
        #expect(parsed.cards[1].quantity == 1)
    }

    // MARK: - Wrapped object alternative keys

    @Test("Wrapped under \"cards\" key")
    func wrappedCardsKey() {
        let text = """
        {"cards": [{"image_index": 0, "cards": [{"card_name": "Nested Card"}]}]}
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].cardName == "Nested Card")
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
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].imageIndex == 0)
        #expect(parsed.cards[0].cardName == "Old Card A")
        #expect(parsed.cards[1].setCode == nil)
        #expect(parsed.cards[1].collectorNumber == nil)
    }

    @Test("Legacy flat array without index falls back to positional")
    func legacyFlatPositional() {
        let text = """
        [
          {"card_name": "First"},
          {"card_name": "Second"}
        ]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 2)
        #expect(parsed.cards[0].imageIndex == 0)
        #expect(parsed.cards[1].imageIndex == 1)
    }

    // MARK: - Tolerance & error paths

    @Test("Strips markdown code fences")
    func stripsMarkdown() {
        let text = """
        ```json
        [{"image_index": 0, "cards": [{"card_name": "Fenced Card"}]}]
        ```
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].cardName == "Fenced Card")
    }

    @Test("Malformed JSON returns empty parsed response")
    func malformedJSON() {
        let parsed = GeminiVisionService.parseBatchResponse(text: "this is not JSON at all")
        #expect(parsed.cards.isEmpty)
        #expect(parsed.analysis == nil)
    }

    @Test("Empty string returns empty parsed response")
    func emptyString() {
        let parsed = GeminiVisionService.parseBatchResponse(text: "")
        #expect(parsed.cards.isEmpty)
        #expect(parsed.analysis == nil)
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
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].cardName == "Valid Card")
    }

    @Test("Tolerates \"name\" field as alias for card_name")
    func nameAlias() {
        let text = """
        [{"image_index": 0, "cards": [{"name": "Alias Card"}]}]
        """
        let parsed = GeminiVisionService.parseBatchResponse(text: text)
        #expect(parsed.cards.count == 1)
        #expect(parsed.cards[0].cardName == "Alias Card")
    }
}
