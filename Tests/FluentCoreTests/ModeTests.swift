import XCTest
@testable import FluentCore

final class ModeTests: XCTestCase {
    func testAllModesHaveInstructionsWithOutputRule() {
        for mode in Mode.allCases {
            XCTAssertEqual(mode.instructions(), mode.defaultPrompt + "\n\n" + Mode.outputRule)
            XCTAssertTrue(mode.instructions().hasSuffix("\n\nOnly reply the result and nothing else."))
        }
    }

    func testAPromptOfYourOwnKeepsTheOutputRule() {
        XCTAssertEqual(Mode.polish.instructions(prompt: "  Make it friendly.\n"),
                       "Make it friendly.\n\n" + Mode.outputRule)
        XCTAssertEqual(Mode.polish.instructions(prompt: " \n"), Mode.polish.instructions())
        let config = AppConfig(baseURL: "u", apiKey: "k", model: "m", prompts: ["translate": "Into English."])
        XCTAssertEqual(config.instructions(for: .interpret), "Into English.\n\n" + Mode.outputRule)
        XCTAssertEqual(config.instructions(for: .fix), Mode.fix.instructions())
    }

    /// The Settings app shows and sends the same built-in prompts; both apps'
    /// tests check them against docs/default-prompts.json.
    func testBuiltInPromptsMatchTheSharedFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/default-prompts.json")
        let shared = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        XCTAssertEqual(shared.count, Mode.allCases.count + 1)
        for mode in Mode.allCases {
            XCTAssertEqual(shared[mode.promptKey], mode.defaultPrompt, mode.promptKey)
        }
        XCTAssertEqual(shared["outputRule"], Mode.outputRule)
    }

    func testNextCycles() {
        XCTAssertEqual(Mode.fix.next, .polish)
        XCTAssertEqual(Mode.polish.next, .interpret)
        XCTAssertEqual(Mode.interpret.next, .fix)
    }
}
