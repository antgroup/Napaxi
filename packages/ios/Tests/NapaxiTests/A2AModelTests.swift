import XCTest
@testable import Napaxi

final class A2AModelTests: XCTestCase {
    func testTaskRecordPreservesLocalPeerSessionEvidence() throws {
        let record = NapaxiA2ATaskRecord.fromJson([
            "task_id": .string("task-1"),
            "envelope_id": .string("env-1"),
            "idempotency_key": .string("idem"),
            "agent_id": .string("agent"),
            "sender": .object(["peer_id": .string("peer-a")]),
            "request": .object([
                "task_id": .string("task-1"),
                "message": .string("hello"),
            ]),
            "status": .string("pending_user_confirmation"),
            "trust": .string("signed_peer"),
            "source": .string("local_transport_require_trusted"),
            "created_at": .string("2026-06-03T00:00:00Z"),
            "updated_at": .string("2026-06-03T00:00:00Z"),
            "session_id": .string("peer-session-1"),
            "peer_message_id": .string("peer-message-1"),
            "result_artifacts": .array([
                .object(["artifact_id": .string("photo-1"), "mime_type": .string("image/jpeg")]),
            ]),
        ])

        XCTAssertEqual(record.sessionId, "peer-session-1")
        XCTAssertEqual(record.peerMessageId, "peer-message-1")
        XCTAssertEqual(record.resultArtifacts.first?.artifactId, "photo-1")
        let encoded = record.toJson()
        XCTAssertEqual(encoded["sessionId"], .string("peer-session-1"))
        XCTAssertEqual(encoded["peerMessageId"], .string("peer-message-1"))
        XCTAssertEqual(encoded["resultArtifacts"], .array([
            .object(["artifactId": .string("photo-1"), "mimeType": .string("image/jpeg")]),
        ]))
    }
}
