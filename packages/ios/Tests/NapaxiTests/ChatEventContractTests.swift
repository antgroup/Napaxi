import XCTest
@testable import Napaxi

// Adapter-parity guard: the iOS NapaxiChatEvent codec must agree with the shared
// wire contract. The values below mirror the cross-adapter fixtures under
// packages/api_contract/fixtures/chat_event/. If a fixture changes, this test
// must change with it (and so must the Flutter and Android codecs).
final class ChatEventContractTests: XCTestCase {
    // mirrors: fixtures/chat_event/tool_call.json
    func testToolCallMatchesSharedContract() throws {
        let event = try NapaxiChatEvent(
            jsonString: """
            {"type":"tool_call","call_id":"call-fixture-001",\
            "name":"home_light_set","arguments":"{\\"room\\":\\"kitchen\\",\\"on\\":true}"}
            """
        )
        XCTAssertEqual(event.type, "tool_call")
        XCTAssertEqual(event.callId, "call-fixture-001")
        XCTAssertEqual(event.toolName, "home_light_set")
        XCTAssertEqual(event.arguments, "{\"room\":\"kitchen\",\"on\":true}")
    }

    // mirrors: fixtures/chat_event/tool_result.json
    func testToolResultMatchesSharedContract() throws {
        let event = try NapaxiChatEvent(
            jsonString: """
            {"type":"tool_result","call_id":"call-fixture-001",\
            "name":"home_light_set","output":"{\\"ok\\":true}","is_error":false}
            """
        )
        XCTAssertEqual(event.type, "tool_result")
        XCTAssertEqual(event.callId, "call-fixture-001")
        XCTAssertEqual(event.toolName, "home_light_set")
        XCTAssertEqual(event.output, "{\"ok\":true}")
        XCTAssertFalse(event.isError)
    }

    // mirrors: fixtures/chat_event/response_delta.json
    func testResponseDeltaMatchesSharedContract() throws {
        let event = try NapaxiChatEvent(
            jsonString: #"{"type":"response_delta","content":"Turning on the kitchen light."}"#
        )
        XCTAssertEqual(event.type, "response_delta")
        XCTAssertEqual(event.content, "Turning on the kitchen light.")
    }

    // mirrors: fixtures/chat_event/run_started.json
    func testRunStartedMatchesSharedContract() throws {
        let event = try NapaxiChatEvent(
            jsonString: """
            {"type":"run_started","run_id":"run-fixture-001",\
            "session_key":"{\\"channel_type\\":\\"app\\",\\"account_id\\":\\"user\\",\
            \\"thread_id\\":\\"thread-fixture-001\\"}","agent_id":"napaxi"}
            """
        )
        XCTAssertEqual(event.type, "run_started")
        XCTAssertEqual(event.runId, "run-fixture-001")
        XCTAssertEqual(event.agentId, "napaxi")
        XCTAssertTrue(event.sessionKey.contains("thread-fixture-001"))
    }
}
