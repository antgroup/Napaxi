import XCTest
@testable import Napaxi

final class SessionRunTrackerTests: XCTestCase {
    func testTrackerPublishesRunLifecycleAndActiveSnapshot() async throws {
        let tracker = NapaxiSessionRunTracker()
        let key = NapaxiSessionKey(channelType: "app", accountId: "user", threadId: "thread")
        var iterator = tracker.updates.makeAsyncIterator()

        let run = try tracker.start(agentId: "napaxi", key: key, now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(tracker.activeRuns.map(\.id), [run.id])
        let started = await iterator.next()
        XCTAssertEqual(started?.status, .running)
        XCTAssertEqual(started?.activity, "Starting")

        let waiting = tracker.apply(
            event: NapaxiChatEvent(raw: .object([
                "type": .string("asking_human"),
                "request_id": .string("hitl-1"),
            ])),
            to: run
        )
        XCTAssertEqual(waiting.status, .waitingForInput)
        XCTAssertEqual(waiting.humanRequestId, "hitl-1")
        let waitingUpdate = await iterator.next()
        XCTAssertEqual(waitingUpdate?.status, .waitingForInput)

        let completed = tracker.complete(waiting)
        XCTAssertTrue(completed.isTerminal)
        XCTAssertTrue(tracker.activeRuns.isEmpty)
        let completedUpdate = await iterator.next()
        XCTAssertEqual(completedUpdate?.status, .completed)
    }

    func testTrackerRejectsDuplicateActiveRun() throws {
        let tracker = NapaxiSessionRunTracker()
        let key = NapaxiSessionKey(threadId: "thread")
        _ = try tracker.start(agentId: "napaxi", key: key)

        XCTAssertThrowsError(try tracker.start(agentId: "napaxi", key: key)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("Session is already running: thread"))
        }
    }

    func testTrackerMarksCancellationLifecycle() throws {
        let tracker = NapaxiSessionRunTracker()
        let key = NapaxiSessionKey(threadId: "thread")
        _ = try tracker.start(agentId: "napaxi", key: key)

        let cancelling = try XCTUnwrap(tracker.cancelling(agentId: "napaxi", key: key))
        XCTAssertEqual(cancelling.status, .cancelling)
        XCTAssertEqual(cancelling.activity, "Stopping")
        XCTAssertEqual(tracker.activeRun(agentId: "napaxi", key: key)?.status, .cancelling)

        let cancelled = tracker.cancelled(cancelling)
        XCTAssertEqual(cancelled.status, .cancelled)
        XCTAssertTrue(cancelled.isTerminal)
        XCTAssertNil(tracker.activeRun(agentId: "napaxi", key: key))
    }

    func testLocallyCancelledRunIsNotReactivatedByLateEvents() throws {
        let tracker = NapaxiSessionRunTracker()
        let key = NapaxiSessionKey(threadId: "thread")
        let run = try tracker.start(agentId: "napaxi", key: key, now: Date(timeIntervalSince1970: 1))
        let cancelling = try XCTUnwrap(tracker.cancelling(agentId: "napaxi", key: key))
        _ = tracker.cancelled(cancelling)

        let lateToolEvent = NapaxiChatEvent(raw: .object([
            "type": .string("tool_call"),
            "name": .string("shell"),
        ]))
        let afterLateEvent = tracker.apply(event: lateToolEvent, to: run)
        XCTAssertEqual(afterLateEvent.status, .cancelled)
        XCTAssertNil(tracker.activeRun(agentId: "napaxi", key: key))

        let afterLateCompletion = tracker.complete(run)
        XCTAssertEqual(afterLateCompletion.status, .cancelled)
        XCTAssertNil(tracker.activeRun(agentId: "napaxi", key: key))
    }

    func testSessionRunStatusEncodingUsesCoreNames() throws {
        let data = try JSONEncoder().encode(NapaxiSessionRunStatus.waitingForInput)
        XCTAssertEqual(String(data: data, encoding: .utf8), #""waiting_for_input""#)

        let decoded = try JSONDecoder().decode(NapaxiSessionRunStatus.self, from: Data(#""waitingForInput""#.utf8))
        XCTAssertEqual(decoded, .waitingForInput)
    }
}
