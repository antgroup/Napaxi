import Foundation
import XCTest
@testable import Napaxi

// contract-fixture: fixtures/project/project_record.json
// contract-fixture: fixtures/project/session_placement.json
final class ProjectContractTests: XCTestCase {
    func testProjectFixturesDecodeThroughPublicModels() throws {
        let project = try JSONDecoder().decode(
            NapaxiProject.self,
            from: try fixtureData("project_record.json")
        )
        let placement = try JSONDecoder().decode(
            NapaxiSessionPlacement.self,
            from: try fixtureData("session_placement.json")
        )

        XCTAssertEqual(project.id, "project-release")
        XCTAssertEqual(placement.projectId, project.id)
        XCTAssertTrue(placement.runtimeMatchesProject(project))
        XCTAssertEqual(placement.revision, 4)
    }

    private func fixtureData(_ name: String) throws -> Data {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: repoRoot.appendingPathComponent(
            "packages/api_contract/fixtures/project/\(name)"
        ))
    }
}
