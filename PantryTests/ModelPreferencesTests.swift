import XCTest
@testable import Pantry

final class ModelPreferencesTests: XCTestCase {

    override func tearDown() {
        ModelPreferences.resetAll()
        super.tearDown()
    }

    func testDefaultsToTheRecommendationForEveryTask() {
        ModelPreferences.resetAll()
        for task in ClaudeTask.allCases {
            XCTAssertEqual(ModelPreferences.model(for: task), task.recommended)
            XCTAssertTrue(ModelPreferences.isUsingRecommendation(for: task))
        }
    }

    func testChoiceIsPersistedPerTaskIndependently() {
        ModelPreferences.set(.opus5, for: .shelfLife)

        XCTAssertEqual(ModelPreferences.model(for: .shelfLife), .opus5)
        XCTAssertFalse(ModelPreferences.isUsingRecommendation(for: .shelfLife))
        // Changing one task must not disturb the others.
        XCTAssertEqual(ModelPreferences.model(for: .reelRecipe), .opus5)
        XCTAssertTrue(ModelPreferences.isUsingRecommendation(for: .photoItems))
    }

    func testResetRestoresRecommendations() {
        ModelPreferences.set(.haiku45, for: .reelRecipe)
        XCTAssertFalse(ModelPreferences.isUsingRecommendation(for: .reelRecipe))

        ModelPreferences.resetAll()
        XCTAssertEqual(ModelPreferences.model(for: .reelRecipe), .opus5)
    }

    /// The recommendations encode a deliberate difficulty ordering: the reel
    /// extractor gets the strongest model, shelf-life the cheapest.
    func testRecommendationsTrackTaskDifficulty() {
        XCTAssertEqual(ClaudeTask.shelfLife.recommended, .haiku45)
        XCTAssertEqual(ClaudeTask.photoItems.recommended, .sonnet5)
        XCTAssertEqual(ClaudeTask.recipeText.recommended, .sonnet5)
        XCTAssertEqual(ClaudeTask.reelRecipe.recommended, .opus5)
    }

    func testEveryTaskExplainsItsRecommendation() {
        for task in ClaudeTask.allCases {
            XCTAssertFalse(task.recommendationReason.isEmpty, "\(task) needs a rationale")
            XCTAssertFalse(task.summary.isEmpty)
        }
    }

    func testUsageIsPricedAgainstTheModelThatRan() {
        let usage = MessagesResponse.Usage(
            inputTokens: 1_000_000, outputTokens: 1_000_000,
            cacheReadInputTokens: nil, cacheCreationInputTokens: nil
        )
        XCTAssertEqual(usage.estimatedUSD(for: .haiku45), 6.0, accuracy: 0.001)
        XCTAssertEqual(usage.estimatedUSD(for: .sonnet5), 18.0, accuracy: 0.001)
        XCTAssertEqual(usage.estimatedUSD(for: .opus5), 30.0, accuracy: 0.001)
    }

    func testRequestUsesTheSelectedModelIdOnTheWire() throws {
        ModelPreferences.set(.haiku45, for: .photoItems)
        let request = MessagesRequest(
            model: ModelPreferences.model(for: .photoItems).rawValue,
            maxTokens: 1024, system: nil, messages: [.user("hi")], outputConfig: nil
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["model"] as? String, "claude-haiku-4-5")
    }
}
