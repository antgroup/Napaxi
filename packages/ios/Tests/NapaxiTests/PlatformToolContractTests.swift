import XCTest
@testable import Napaxi

// Adapter-parity guard: the iOS platform-tool contract (the hand-maintained
// `toolDefinitions` array and `platformToolNames` set in PlatformTools.swift)
// must agree with the shared cross-adapter fixture, which is generated from and
// pinned to Rust core (crates/core/src/platform_capabilities.rs) by the Rust
// test `descriptors_match_shared_contract_fixture`. This stops the iOS copy
// from silently drifting from core — exactly the drift this test was added to
// catch (iOS send_sms / get_clipboard descriptions had diverged).
//
// `effect` is intentionally NOT compared: core marks every tool "external",
// but iOS deliberately localizes read-only tools (e.g. get_clipboard) to
// "read". The fixture records core's "external" values, so the guard pins
// name + description + parameters and leaves `effect` as an iOS-local concern.
//
// contract-fixture: fixtures/platform_tools/tool_descriptors.json
final class PlatformToolContractTests: XCTestCase {
    private func fixtureEntries(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [[String: Any]] {
        // packages/ios/Tests/NapaxiTests/<thisFile> -> repo root is 5 levels up.
        let thisFile = URL(fileURLWithPath: "\(file)")
        let repoRoot = thisFile
            .deletingLastPathComponent() // NapaxiTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // packages
            .deletingLastPathComponent() // repo root
        let fixtureURL = repoRoot.appendingPathComponent(
            "packages/api_contract/fixtures/platform_tools/tool_descriptors.json"
        )
        let data = try Data(contentsOf: fixtureURL)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            XCTFail("platform_tools fixture is not a JSON array", file: file, line: line)
            return []
        }
        return array
    }

    func testPlatformToolNamesMatchSharedContract() throws {
        let fixtureNamesList = try fixtureEntries().compactMap { $0["name"] as? String }
        let fixtureNames = Set(fixtureNamesList)
        XCTAssertEqual(fixtureNames.count, fixtureNamesList.count)

        // Both hand-maintained copies of the name list must match the fixture.
        XCTAssertEqual(NapaxiPlatformToolProvider.platformToolNames, fixtureNames)
        let definitionNames = Set(NapaxiPlatformToolProvider.getToolDefinitions().map(\.name))
        XCTAssertEqual(definitionNames, fixtureNames)
    }

    func testPlatformToolDescriptionsMatchSharedContract() throws {
        let definitionsByName = Dictionary(
            uniqueKeysWithValues: NapaxiPlatformToolProvider.getToolDefinitions().map { ($0.name, $0) }
        )

        for entry in try fixtureEntries() {
            guard let name = entry["name"] as? String else {
                XCTFail("fixture entry missing name")
                continue
            }
            guard let definition = definitionsByName[name] else {
                XCTFail("iOS is missing platform tool '\(name)' present in the shared fixture")
                continue
            }
            let expectedDescription = entry["description"] as? String
            XCTAssertEqual(
                definition.description,
                expectedDescription,
                "iOS description for '\(name)' drifted from the shared contract fixture"
            )
        }
    }
}
