import XCTest
@testable import Napaxi

// Adapter-parity guard: the iOS codecs for capability status, session-run
// records, and automation jobs must agree with the shared wire contract. The
// values below mirror the cross-adapter fixtures under
// packages/api_contract/fixtures/{capability,session_run,automation}/. If a
// fixture changes, this test must change with it (and so must the Flutter and
// Android codecs).
final class RuntimeContractTests: XCTestCase {
    private func object(_ jsonString: String) throws -> [String: NapaxiJSONValue] {
        let value = try NapaxiRawJSON(jsonString: jsonString).value
        guard let object = value.objectValue else {
            throw NapaxiError.invalidJSON("expected JSON object")
        }
        return object
    }

    // mirrors: fixtures/capability/capability_status.json
    func testCapabilityStatusMatchesSharedContract() throws {
        let status = NapaxiCapabilityStatus.fromJson(
            try object(
                """
                {"definition":{"id":"napaxi.tool.custom_host","kind":"tool","version":"1",
                "platforms":["all"],"config_schema":{},"risk":"medium",
                "requirements":["host_tool_dispatcher"],"default_enabled":false,
                "activation":"host"},"registered":true,"available":true,"enabled":true}
                """
            )
        )
        XCTAssertTrue(status.registered)
        XCTAssertTrue(status.available)
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.definition.id, "napaxi.tool.custom_host")
        XCTAssertEqual(status.definition.kind, "tool")
        XCTAssertEqual(status.definition.risk, "medium")
        XCTAssertEqual(status.definition.activation, "host")
        XCTAssertFalse(status.definition.defaultEnabled)
    }

    // mirrors: fixtures/session_run/session_run_record.json
    func testSessionRunRecordMatchesSharedContract() throws {
        let records = try decodeSessionRunRecords(
            """
            [{"runId":"run-fixture-001","status":"succeeded","agentId":"napaxi",
            "sessionKey":"{}","threadId":"thread-fixture-001","startedAt":1717800000000,
            "completedAt":1717800002500,"durationMs":2500,"evidenceKind":"tool_observed",
            "verification":"verified","toolCallCount":1,
            "evidence":[{"kind":"tool_observed","source":"home_light_set","isError":false}],
            "summary":"Turned on the kitchen light.","childRunIds":[]}]
            """
        )
        XCTAssertEqual(records.count, 1)
        let record = records[0]
        XCTAssertEqual(record.runId, "run-fixture-001")
        XCTAssertEqual(record.status, .succeeded)
        XCTAssertEqual(record.agentId, "napaxi")
        XCTAssertEqual(record.threadId, "thread-fixture-001")
        XCTAssertEqual(record.evidenceKind, .toolObserved)
        XCTAssertEqual(record.verification, .verified)
        XCTAssertEqual(record.toolCallCount, 1)
        XCTAssertEqual(record.evidence.count, 1)
        XCTAssertEqual(record.evidence[0].source, "home_light_set")
        XCTAssertFalse(record.evidence[0].isError)
    }

    // mirrors: fixtures/automation/automation_job.json
    func testAutomationJobMatchesSharedContract() throws {
        let job = NapaxiAutomationJob.fromJson(
            try object(
                """
                {"id":"job-fixture-001","name":"Morning briefing","enabled":true,
                "accountId":"user","agentId":"napaxi",
                "trigger":{"kind":"localTime","hour":8,"minute":30,
                "timezone":"America/New_York","daysOfWeek":[1,2,3,4,5]},
                "payload":{"kind":"agentTurn","message":"Give me my morning briefing.",
                "sessionMode":"isolated","maxIterations":4},
                "policy":{"requiresUserVisibleNotification":true,"allowHighRiskTools":false,
                "maxRunDurationMs":120000,"maxRetries":2,"retryBackoffMs":[1000,5000]},
                "state":{},"createdAt":1717800000000,"updatedAt":1717800000000}
                """
            )
        )
        XCTAssertEqual(job.id, "job-fixture-001")
        XCTAssertTrue(job.enabled)
        XCTAssertEqual(job.agentId, "napaxi")
        XCTAssertEqual(job.trigger.kind, "localTime")
        XCTAssertEqual(job.trigger.hour, 8)
        XCTAssertEqual(job.trigger.minute, 30)
        XCTAssertEqual(job.trigger.timezone, "America/New_York")
        XCTAssertEqual(job.payload.kind, "agentTurn")
        XCTAssertEqual(job.payload.message, "Give me my morning briefing.")
        XCTAssertEqual(job.payload.maxIterations, 4)
        XCTAssertTrue(job.policy.requiresUserVisibleNotification)
        XCTAssertEqual(job.policy.maxRetries, 2)
    }
}
