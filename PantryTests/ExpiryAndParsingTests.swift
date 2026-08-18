import XCTest
@testable import Pantry

final class ExpiryStatusTests: XCTestCase {

    private let calendar = Calendar.current

    private func status(daysFromNow days: Int) -> ExpiryStatus {
        let date = calendar.date(byAdding: .day, value: days, to: Date())!
        return ExpiryStatus.status(for: date)
    }

    func testBucketing() {
        if case .expired(let daysAgo) = status(daysFromNow: -2) {
            XCTAssertEqual(daysAgo, 2)
        } else { XCTFail("Expected expired") }

        if case .today = status(daysFromNow: 0) {} else { XCTFail("Expected today") }
        if case .soon = status(daysFromNow: 2) {} else { XCTFail("Expected soon") }
        if case .thisWeek = status(daysFromNow: 6) {} else { XCTFail("Expected thisWeek") }
        if case .fresh = status(daysFromNow: 40) {} else { XCTFail("Expected fresh") }
        if case .unknown = ExpiryStatus.status(for: nil) {} else { XCTFail("Expected unknown") }
    }

    /// An item expiring later today must not read as already expired just
    /// because the clock has moved past the time it was added.
    func testComparisonIsCalendarDayBased() {
        let laterToday = calendar.date(byAdding: .minute, value: 1, to: calendar.startOfDay(for: Date()))!
        if case .today = ExpiryStatus.status(for: laterToday) {} else {
            XCTFail("Same calendar day should be .today regardless of time")
        }
    }

    func testOrderingIsMostUrgentFirst() {
        let ordered = [
            status(daysFromNow: 40),
            ExpiryStatus.status(for: nil),
            status(daysFromNow: -1),
            status(daysFromNow: 2),
            status(daysFromNow: 0),
        ].sorted()

        XCTAssertEqual(ordered.map(\.sortRank), [0, 1, 2, 4, 5])
    }

    func testOnlyNearTermItemsNeedAttention() {
        XCTAssertTrue(status(daysFromNow: -1).needsAttention)
        XCTAssertTrue(status(daysFromNow: 3).needsAttention)
        XCTAssertTrue(status(daysFromNow: 7).needsAttention)
        XCTAssertFalse(status(daysFromNow: 30).needsAttention)
        XCTAssertFalse(ExpiryStatus.status(for: nil).needsAttention)
    }
}

final class MeasureUnitTests: XCTestCase {

    func testParsesCommonRecipeUnits() {
        XCTAssertEqual(MeasureUnit.parse("tbsp"), .tablespoon)
        XCTAssertEqual(MeasureUnit.parse("Tablespoons"), .tablespoon)
        XCTAssertEqual(MeasureUnit.parse("g"), .gram)
        XCTAssertEqual(MeasureUnit.parse("KG"), .kilogram)
        XCTAssertEqual(MeasureUnit.parse("cloves"), .piece)
        XCTAssertEqual(MeasureUnit.parse(nil), .piece)
    }

    func testFormatting() {
        XCTAssertEqual(MeasureUnit.gram.format(250), "250 g")
        XCTAssertEqual(MeasureUnit.piece.format(3), "3")
        XCTAssertEqual(MeasureUnit.cup.format(2), "2 cups")
        XCTAssertEqual(MeasureUnit.cup.format(1), "1 cup")
    }
}

final class ShelfLifeRulesTests: XCTestCase {

    func testKnownItemsResolveOffline() {
        XCTAssertEqual(ShelfLifeRules.estimate(for: "milk")?.days, 7)
        XCTAssertEqual(ShelfLifeRules.estimate(for: "Bananas")?.days, 5)
    }

    /// "sweet potato" must not fall through to the shorter "potato" entry.
    func testMostSpecificEntryWins() {
        let sweet = ShelfLifeRules.estimate(for: "sweet potatoes")?.days
        let plain = ShelfLifeRules.estimate(for: "potatoes")?.days
        XCTAssertEqual(sweet, 25)
        XCTAssertEqual(plain, 30)
    }

    func testUnknownItemFallsThroughSoClaudeCanBeAsked() {
        XCTAssertNil(ShelfLifeRules.estimate(for: "gochujang"))
    }

    func testCategoryFallbackIsUsedWhenOffered() {
        let estimate = ShelfLifeRules.estimate(for: "gochujang", category: .condiment)
        XCTAssertEqual(estimate?.days, 180)
    }

    func testPerishablesAreConservative() {
        for name in ["chicken", "fish", "prawns"] {
            let days = ShelfLifeRules.estimate(for: name)?.days ?? .max
            XCTAssertLessThanOrEqual(days, 3, "\(name) should be flagged quickly")
        }
    }
}

final class InstagramFetcherTests: XCTestCase {

    func testExtractsShortcodeFromReelURLs() {
        XCTAssertEqual(
            InstagramFetcher.shortcode(from: "https://www.instagram.com/reel/DAaXQZ_x9Vf/"),
            "DAaXQZ_x9Vf"
        )
        XCTAssertEqual(
            InstagramFetcher.shortcode(from: "https://instagram.com/reels/AbC-123_x/?igsh=xyz"),
            "AbC-123_x"
        )
        XCTAssertEqual(
            InstagramFetcher.shortcode(from: "https://www.instagram.com/p/tsxp1hhQTG/"),
            "tsxp1hhQTG"
        )
        // Profile-scoped reel links, which the share sheet sometimes produces.
        XCTAssertEqual(
            InstagramFetcher.shortcode(from: "https://www.instagram.com/someuser/reel/XyZ123/"),
            "XyZ123"
        )
    }

    func testRejectsNonInstagramLinks() {
        XCTAssertNil(InstagramFetcher.shortcode(from: "https://tiktok.com/@user/video/123"))
        XCTAssertNil(InstagramFetcher.shortcode(from: "not a url"))
    }
}

final class SchemaEncodingTests: XCTestCase {

    /// The structured-output schema has to survive JSON encoding exactly as
    /// written — a malformed schema is a 400 from the API at runtime.
    func testSchemaEncodesToValidJSON() throws {
        let schema = Schema.object(
            properties: [
                "name": Schema.string("The name"),
                "count": Schema.integer("How many"),
                "tags": Schema.array(of: Schema.string("A tag")),
                "note": Schema.nullable("string", "Optional note"),
            ],
            required: ["name", "count", "tags", "note"]
        )

        let data = try JSONEncoder().encode(schema)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        XCTAssertEqual((object["required"] as? [String])?.sorted(), ["count", "name", "note", "tags"])

        let properties = try XCTUnwrap(object["properties"] as? [String: Any])
        let note = try XCTUnwrap(properties["note"] as? [String: Any])
        XCTAssertEqual(note["type"] as? [String], ["string", "null"])
    }

    func testRequestEncodesWireFieldNames() throws {
        let request = MessagesRequest(
            model: "claude-opus-5",
            maxTokens: 1024,
            system: "You are helpful.",
            messages: [.user("hello")],
            outputConfig: OutputConfig(effort: "low", format: nil)
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["max_tokens"] as? Int, 1024)
        XCTAssertNotNil(object["output_config"])
        XCTAssertNil(object["maxTokens"], "camelCase must not leak onto the wire")
    }

    func testImageBlockEncodesBase64Source() throws {
        let block = ContentBlock.image(base64: "QUJD", mediaType: "image/jpeg")
        let data = try JSONEncoder().encode(block)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["type"] as? String, "image")
        let source = try XCTUnwrap(object["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "QUJD")
    }
}
