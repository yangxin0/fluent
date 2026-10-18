import XCTest
@testable import FluentCore

/// The sample configs in docs/config-examples, which the Settings app's Go
/// tests read too (TestConfigExamples): both apps must make the same of each
/// file, since they share no code (docs/config.md).
final class ConfigExamplesTests: XCTestCase {
    private struct Expected: Decodable {
        var configured: Bool
        var problem: String?
    }

    func testBothAppsReadTheExamplesAlike() throws {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/config-examples")
        let expected = try JSONDecoder().decode(
            [String: Expected].self, from: Data(contentsOf: folder.appendingPathComponent("expected.json")))
        XCTAssertFalse(expected.isEmpty)
        for (name, want) in expected.sorted(by: { $0.key < $1.key }) {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            var configured = false
            var problem: String?
            do {
                configured = try JSONDecoder().decode(AppConfig.self, from: data).isConfigured
            } catch {
                problem = ConfigStore.describe(error)
            }
            XCTAssertEqual(configured, want.configured, name)
            XCTAssertEqual(problem, want.problem, name)
        }
    }
}
