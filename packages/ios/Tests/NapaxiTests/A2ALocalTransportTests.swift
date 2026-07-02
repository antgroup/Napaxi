import XCTest
@testable import Napaxi

final class A2ALocalTransportTests: XCTestCase {
    func testNativeLocalTransportStartsStopsAndBuffersInboundEvents() throws {
        let transport = NapaxiA2ALocalTransport(rawAPI: NapaxiRawAPI(handle: -1))
        defer { _ = transport.stop() }

        _ = transport.start(
            peerId: "ios-peer-a",
            agentId: "agent-a",
            displayName: "Phone A",
            publicKey: "public-a"
        )

        let ready = waitForStatus(timeout: 5) {
            let status = transport.status()
            return status.running && status.listenerPort > 0 ? status : nil
        }
        XCTAssertTrue(ready.supported)
        XCTAssertTrue(ready.running)
        XCTAssertEqual(ready.transport, "lan_tcp_jsonl")
        XCTAssertEqual(ready.serviceType, "_napaxi-a2a._tcp.")
        XCTAssertEqual(ready.peerId, "ios-peer-a")

        let message = NapaxiA2APeerMessage(json: [
            "messageId": .string("message-1"),
            "sessionId": .string("session-1"),
            "fromPeerId": .string("ios-peer-b"),
            "toPeerId": .string("ios-peer-a"),
            "kind": .string("task_progress"),
            "createdAt": .string("2026-06-03T00:00:00Z"),
            "expiresAt": .string("2026-06-03T00:05:00Z"),
            "nonce": .string("nonce-1"),
            "idempotencyKey": .string("idem-1"),
            "payload": .object([
                "taskId": .string("task-1"),
                "message": .string("accepted"),
                "progress": .object(["status": .string("accepted")]),
            ]),
        ])

        XCTAssertTrue(transport.send(message, endpoint: "tcp://127.0.0.1:\(ready.listenerPort)/a2a"))

        let event = waitForEvent(timeout: 5, transport: transport) { event in
            event.action == "a2aLocalPeerMessage" && event.message?.messageId == "message-1"
        }
        XCTAssertEqual(event.message?.sessionId, "session-1")
        XCTAssertEqual(event.payload["source"], .string("lan_tcp_jsonl"))
        XCTAssertTrue(event.payload["recordError"]?.stringValue?.contains("only available on iOS") == true)

        let stopped = transport.stop()
        XCTAssertFalse(stopped.running)
    }

    func testNativeLocalTransportReportsInfoPlistReadiness() {
        let transport = NapaxiA2ALocalTransport(rawAPI: NapaxiRawAPI(handle: -1))
        let status = transport.status()

        XCTAssertTrue(status.supported)
        XCTAssertEqual(status.transport, "lan_tcp_jsonl")
        XCTAssertEqual(status.serviceType, "_napaxi-a2a._tcp.")
        XCTAssertEqual(transport.checkPermission(), status.reason.isEmpty)
    }

    private func waitForStatus(
        timeout: TimeInterval,
        _ predicate: () -> NapaxiA2ALocalTransportStatus?
    ) -> NapaxiA2ALocalTransportStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = predicate() {
                return status
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return predicate() ?? NapaxiA2ALocalTransport(rawAPI: NapaxiRawAPI(handle: -1)).status()
    }

    private func waitForEvent(
        timeout: TimeInterval,
        transport: NapaxiA2ALocalTransport,
        _ predicate: (NapaxiA2ALocalTransportEvent) -> Bool
    ) -> NapaxiA2ALocalTransportEvent {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = transport.localTransportEvents().first(where: predicate) {
                return event
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return transport.localTransportEvents().first(where: predicate) ??
            NapaxiA2ALocalTransportEvent(fromEvent: ["action": .string("missing")])
    }
}
