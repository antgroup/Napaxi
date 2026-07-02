import XCTest
@testable import Napaxi

final class SessionRunModelTests: XCTestCase {
    func testSessionRunListDefaultLimitMirrorsFlutter() {
        XCTAssertEqual(NapaxiSessionRunAPI.defaultListLimit, 100)
    }

    func testSessionRunRecordDecodesFlutterCompatibleKeys() throws {
        let json = """
        {
          "run_id": "run-1",
          "status": "succeeded",
          "agent_id": "napaxi",
          "session_key": "app:default:thread",
          "thread_id": "thread",
          "started_at": "100",
          "completed_at": 150,
          "duration_ms": 50,
          "evidence_kind": "tool_observed",
          "verification": "verified",
          "tool_call_count": "2",
          "evidence": [
            {
              "kind": "side_effect_observed",
              "source": "tool",
              "effect": "calendar_event",
              "is_error": true,
              "digest": "abc"
            }
          ],
          "summary": "done",
          "parent_run_id": "parent",
          "child_run_ids": ["child", 7, null],
          "unknown_future_field": true
        }
        """

        let run = try JSONDecoder().decode(NapaxiSessionRunRecord.self, from: Data(json.utf8))

        XCTAssertEqual(run.runId, "run-1")
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertEqual(run.agentId, "napaxi")
        XCTAssertEqual(run.sessionKey, "app:default:thread")
        XCTAssertEqual(run.threadId, "thread")
        XCTAssertEqual(run.startedAt, 100)
        XCTAssertEqual(run.completedAt, 150)
        XCTAssertEqual(run.durationMs, 50)
        XCTAssertEqual(run.evidenceKind, .toolObserved)
        XCTAssertEqual(run.verification, .verified)
        XCTAssertEqual(run.toolCallCount, 2)
        XCTAssertEqual(run.evidence.first?.kind, .sideEffectObserved)
        XCTAssertEqual(run.evidence.first?.source, "tool")
        XCTAssertEqual(run.evidence.first?.effect, "calendar_event")
        XCTAssertEqual(run.evidence.first?.isError, true)
        XCTAssertEqual(run.evidence.first?.digest, "abc")
        XCTAssertEqual(run.summary, "done")
        XCTAssertEqual(run.parentRunId, "parent")
        XCTAssertEqual(run.childRunIds, ["child"])
        XCTAssertEqual(run.raw["unknown_future_field"], .bool(true))
    }

    func testSessionRunRecordConstructorEncodesFlutterShape() throws {
        let evidence = NapaxiRunEvidence(
            kind: .detachedTaskObserved,
            source: "automation",
            effect: "wake",
            digest: "digest"
        )
        let run = NapaxiSessionRunRecord(
            runId: "run-2",
            status: .running,
            agentId: "napaxi",
            sessionKey: "key",
            threadId: "thread",
            startedAt: 1,
            evidenceKind: .replyOnly,
            verification: .notRequired,
            evidence: [evidence],
            childRunIds: ["child"]
        )

        let value = try NapaxiRawJSON(jsonString: run.jsonString()).value
        guard case .object(let object) = value else {
            return XCTFail("session run should encode as object")
        }

        XCTAssertEqual(object["runId"], .string("run-2"))
        XCTAssertEqual(object["status"], .string("running"))
        XCTAssertEqual(object["agentId"], .string("napaxi"))
        XCTAssertEqual(object["evidenceKind"], .string("reply_only"))
        XCTAssertEqual(object["verification"], .string("not_required"))
        if case .array(let evidenceArray)? = object["evidence"],
           case .object(let first)? = evidenceArray.first {
            XCTAssertEqual(first["kind"], .string("detached_task_observed"))
            XCTAssertEqual(first["source"], .string("automation"))
            XCTAssertEqual(first["isError"], .bool(false))
        } else {
            XCTFail("evidence should encode as object array")
        }
        XCTAssertEqual(object["childRunIds"], .array([.string("child")]))
    }

    func testSessionRunStableStringsKeepUnknownValues() {
        XCTAssertEqual(NapaxiSessionRunRecordStatus(rawValue: "new_status").rawValue, "new_status")
        XCTAssertEqual(NapaxiRunEvidenceKind(rawValue: "new_kind").rawValue, "new_kind")
        XCTAssertEqual(NapaxiRunVerification(rawValue: "new_verification").rawValue, "new_verification")
        XCTAssertEqual(SessionRunRecordStatus.fromWire("running"), .running)
        XCTAssertEqual(SessionRunRecordStatus.fromWire("new_status"), .unknown)
        XCTAssertEqual(SessionRunRecordStatus.running.wireName, "running")
        XCTAssertEqual(RunEvidenceKind.fromWire("tool_observed"), .toolObserved)
        XCTAssertEqual(RunEvidenceKind.fromWire(nil), .unknown)
        XCTAssertEqual(RunEvidenceKind.toolObserved.wireName, "tool_observed")
        XCTAssertEqual(RunVerification.fromWire("verified"), .verified)
        XCTAssertEqual(RunVerification.fromWire("new_verification"), .unknown)
        XCTAssertEqual(RunVerification.verified.wireName, "verified")
    }

    func testSessionRunTypedAccessorsMapUnknownWireValuesLikeFlutter() throws {
        let json = """
        {
          "run_id": "run-unknown",
          "status": "future_status",
          "agent_id": "napaxi",
          "session_key": "app:default:thread",
          "thread_id": "thread",
          "started_at": 1,
          "evidence_kind": "future_evidence",
          "verification": "future_verification",
          "evidence": [
            {"kind": "future_kind", "source": "tool"}
          ]
        }
        """

        let run = try JSONDecoder().decode(NapaxiSessionRunRecord.self, from: Data(json.utf8))

        XCTAssertEqual(run.status, .unknown)
        XCTAssertEqual(run.evidenceKind, .unknown)
        XCTAssertEqual(run.verification, .unknown)
        XCTAssertEqual(run.evidence.first?.kind, .unknown)
        XCTAssertEqual(run.raw["status"], .string("future_status"))
        XCTAssertEqual(run.raw["evidence_kind"], .string("future_evidence"))
    }

    func testDecodeSessionRunRecordsMirrorsFlutterHelper() throws {
        let raw = """
        [
          {
            "run_id": "run-1",
            "status": "running",
            "agent_id": "napaxi",
            "session_key": "app:default:thread",
            "thread_id": "thread",
            "started_at": 1,
            "evidence_kind": "reply_only",
            "verification": "not_required"
          },
          "ignored",
          {
            "runId": "run-2",
            "status": "succeeded",
            "agentId": "napaxi",
            "sessionKey": "app:default:thread-2",
            "threadId": "thread-2",
            "startedAt": "2",
            "evidenceKind": "tool_observed",
            "verification": "verified"
          }
        ]
        """

        let runs = try decodeSessionRunRecords(raw)

        XCTAssertEqual(runs.map(\.runId), ["run-1", "run-2"])
        XCTAssertEqual(runs[1].startedAt, 2)
        XCTAssertEqual(runs[1].evidenceKind, .toolObserved)
        XCTAssertEqual(try NapaxiSessionRunAPI.decodeRecords(from: .object(["error": .string("ignored")])).count, 0)
        XCTAssertEqual(try NapaxiSessionRunAPI.decodeRecords(from: .string("ignored")).count, 0)
        XCTAssertEqual(try decodeSessionRunRecords(#"{"run_id":"not-array"}"#), [])
        XCTAssertThrowsError(try decodeSessionRunRecords("not json"))
    }

    func testSessionRunGetDecoderMirrorsFlutterNullAndErrorHandling() throws {
        let run = try XCTUnwrap(NapaxiSessionRunAPI.decodeRecordOrNil(from: .object([
            "run_id": .string("run-1"),
            "status": .string("running"),
            "agent_id": .string("napaxi"),
            "session_key": .string("app:default:thread"),
            "thread_id": .string("thread"),
            "started_at": .number(1),
            "evidence_kind": .string("reply_only"),
            "verification": .string("not_required"),
        ])))

        XCTAssertEqual(run.runId, "run-1")
        XCTAssertNil(try NapaxiSessionRunAPI.decodeRecordOrNil(from: .null))
        XCTAssertNil(try NapaxiSessionRunAPI.decodeRecordOrNil(from: .object(["error": .string("not found")])))
        XCTAssertNil(try NapaxiSessionRunAPI.decodeRecordOrNil(from: .array([])))
        XCTAssertNil(try NapaxiSessionRunAPI.decodeRecordOrNil(from: .string("unexpected")))
    }
}
