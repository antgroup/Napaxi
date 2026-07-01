import XCTest
@testable import Napaxi

final class EvolutionModelTests: XCTestCase {
    func testEvolutionEngineHelpersMirrorFlutterAPISurface() {
        let listPending: (NapaxiEngine) throws -> [[String: NapaxiJSONValue]] = { engine in
            try engine.listPendingEvolution()
        }
        let applyPending: (NapaxiEngine, String) throws -> [String: NapaxiJSONValue] = { engine, pendingId in
            try engine.applyPendingEvolution(pendingId)
        }
        let rejectPending: (NapaxiEngine, String) throws -> [String: NapaxiJSONValue] = { engine, pendingId in
            try engine.rejectPendingEvolution(pendingId)
        }
        let listRuns: (NapaxiEngine, [String]) throws -> [NapaxiEvolutionRun] = { engine, runIds in
            try engine.listEvolutionRuns(runIds: runIds)
        }
        let listDiagnostics: (NapaxiEngine) throws -> [NapaxiEvolutionDiagnostic] = { engine in
            try engine.listEvolutionDiagnostics()
        }
        let runReview: (NapaxiEngine, String, Bool) throws -> NapaxiSkillConsolidationReviewResult = { engine, agentId, dryRun in
            try engine.runSkillConsolidationReview(agentId: agentId, dryRun: dryRun)
        }

        XCTAssertNotNil(listPending)
        XCTAssertNotNil(applyPending)
        XCTAssertNotNil(rejectPending)
        XCTAssertNotNil(listRuns)
        XCTAssertNotNil(listDiagnostics)
        XCTAssertNotNil(runReview)
    }

    func testEvolutionRunDecodesFlutterCompatibleFields() throws {
        let run = try JSONDecoder().decode(
            NapaxiEvolutionRun.self,
            from: Data(#"{"id":"run1","agent_id":"napaxi","thread_id":"thread","review_type":"skill_consolidation","status":"completed","queued_at":"2026-01-01T00:00:00Z","started_at":"2026-01-01T00:01:00Z","completed_at":"2026-01-01T00:02:00Z","suggestions_count":3,"auto_applied_count":1,"pending_count":2}"#.utf8)
        )
        let stringCountRun = try JSONDecoder().decode(
            NapaxiEvolutionRun.self,
            from: Data(#"{"id":"run2","agent_id":"napaxi","thread_id":"thread","review_type":"skill_consolidation","status":"running","queued_at":"2026-01-01T00:00:00Z","suggestions_count":"3","auto_applied_count":"1","pending_count":"2"}"#.utf8)
        )
        let fractionalCountRun = try JSONDecoder().decode(
            NapaxiEvolutionRun.self,
            from: Data(#"{"id":"run3","agent_id":"napaxi","thread_id":"thread","review_type":"skill_consolidation","status":"running","queued_at":"2026-01-01T00:00:00Z","suggestions_count":3.5,"auto_applied_count":1.5,"pending_count":2.5}"#.utf8)
        )

        XCTAssertEqual(run.id, "run1")
        XCTAssertEqual(run.agentId, "napaxi")
        XCTAssertEqual(run.threadId, "thread")
        XCTAssertEqual(run.reviewType, "skill_consolidation")
        XCTAssertEqual(run.status, .completed)
        XCTAssertEqual(run.queuedAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(run.startedAt, "2026-01-01T00:01:00Z")
        XCTAssertEqual(run.completedAt, "2026-01-01T00:02:00Z")
        XCTAssertEqual(run.suggestionsCount, 3)
        XCTAssertEqual(run.autoAppliedCount, 1)
        XCTAssertEqual(run.pendingCount, 2)
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(stringCountRun.suggestionsCount, 0)
        XCTAssertEqual(stringCountRun.autoAppliedCount, 0)
        XCTAssertEqual(stringCountRun.pendingCount, 0)
        XCTAssertEqual(fractionalCountRun.suggestionsCount, 0)
        XCTAssertEqual(fractionalCountRun.autoAppliedCount, 0)
        XCTAssertEqual(fractionalCountRun.pendingCount, 0)
    }

    func testEvolutionDiagnosticDecodesNestedFields() throws {
        let diagnostic = try JSONDecoder().decode(
            NapaxiEvolutionDiagnostic.self,
            from: Data(#"{"id":"diag1","created_at":"2026-01-01T00:00:00Z","agent_id":"napaxi","thread_id":"thread","review_type":"skill_consolidation","trigger_reason":"manual","input_summary":{"skills":2},"tool_calls":["skill.list"],"suggestions_count":1,"pending_count":1,"auto_applied_count":0,"apply_result":"queued","failure_reason":"none"}"#.utf8)
        )

        XCTAssertEqual(diagnostic.id, "diag1")
        XCTAssertEqual(diagnostic.createdAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(diagnostic.inputSummary["skills"], .number(2))
        XCTAssertEqual(diagnostic.toolCalls, ["skill.list"])
        XCTAssertEqual(diagnostic.suggestionsCount, 1)
        XCTAssertEqual(diagnostic.pendingCount, 1)
        XCTAssertEqual(diagnostic.applyResult, "queued")
        XCTAssertEqual(diagnostic.failureReason, "none")

        let stringCountDiagnostic = try JSONDecoder().decode(
            NapaxiEvolutionDiagnostic.self,
            from: Data(#"{"id":"diag2","created_at":"2026-01-01T00:00:00Z","suggestions_count":"1","pending_count":"1","auto_applied_count":"0"}"#.utf8)
        )
        let fractionalCountDiagnostic = try JSONDecoder().decode(
            NapaxiEvolutionDiagnostic.self,
            from: Data(#"{"id":"diag3","created_at":"2026-01-01T00:00:00Z","suggestions_count":1.5,"pending_count":1.5,"auto_applied_count":0.5}"#.utf8)
        )
        XCTAssertEqual(stringCountDiagnostic.suggestionsCount, 0)
        XCTAssertEqual(stringCountDiagnostic.pendingCount, 0)
        XCTAssertEqual(stringCountDiagnostic.autoAppliedCount, 0)
        XCTAssertEqual(fractionalCountDiagnostic.suggestionsCount, 0)
        XCTAssertEqual(fractionalCountDiagnostic.pendingCount, 0)
        XCTAssertEqual(fractionalCountDiagnostic.autoAppliedCount, 0)
    }

    func testEvolutionTypedListDecodersSurfaceFlutterErrors() throws {
        let validRun: [String: NapaxiJSONValue] = [
            "id": .string("run1"),
            "agent_id": .string("napaxi"),
            "thread_id": .string("thread"),
            "review_type": .string("skill_consolidation"),
            "status": .string("completed"),
            "queued_at": .string("2026-01-01T00:00:00Z"),
            "suggestions_count": .number(1),
        ]
        let runs = try NapaxiEvolutionAPI.decodeEvolutionRuns(from: .array([.object(validRun)]))
        XCTAssertEqual(runs.first?.id, "run1")
        XCTAssertEqual(runs.first?.suggestionsCount, 1)

        var missingRunId = validRun
        missingRunId.removeValue(forKey: "id")
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionRuns(from: .array([.object(missingRunId)])))

        var malformedRunDate = validRun
        malformedRunDate["queued_at"] = .string("not-a-date")
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionRuns(from: .array([.object(malformedRunDate)])))

        var malformedRunCount = validRun
        malformedRunCount["suggestions_count"] = .string("1")
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionRuns(from: .array([.object(malformedRunCount)])))

        let validDiagnostic: [String: NapaxiJSONValue] = [
            "id": .string("diag1"),
            "created_at": .string("2026-01-01T00:00:00Z"),
            "agent_id": .string("napaxi"),
            "thread_id": .string("thread"),
            "review_type": .string("skill_consolidation"),
            "trigger_reason": .string("manual"),
            "input_summary": .object(["skills": .number(2)]),
            "tool_calls": .array([.string("skill.list")]),
            "pending_count": .number(1),
        ]
        let diagnostics = try NapaxiEvolutionAPI.decodeEvolutionDiagnostics(from: .array([.object(validDiagnostic)]))
        XCTAssertEqual(diagnostics.first?.id, "diag1")
        XCTAssertEqual(diagnostics.first?.toolCalls, ["skill.list"])

        var missingDiagnosticDate = validDiagnostic
        missingDiagnosticDate.removeValue(forKey: "created_at")
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionDiagnostics(from: .array([.object(missingDiagnosticDate)])))

        var malformedDiagnosticSummary = validDiagnostic
        malformedDiagnosticSummary["input_summary"] = .array([])
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionDiagnostics(from: .array([.object(malformedDiagnosticSummary)])))

        var malformedDiagnosticToolCalls = validDiagnostic
        malformedDiagnosticToolCalls["tool_calls"] = .array([.number(1)])
        XCTAssertThrowsError(try NapaxiEvolutionAPI.decodeEvolutionDiagnostics(from: .array([.object(malformedDiagnosticToolCalls)])))
    }

    func testSkillConsolidationReviewResultDecodesFlutterCompatibleFields() throws {
        let result = try JSONDecoder().decode(
            NapaxiSkillConsolidationReviewResult.self,
            from: Data(#"{"reviewed":true,"dry_run":false,"suggestions_count":2,"pending_count":1,"pending_id":"pending1","actions":[{"kind":"merge"}],"warnings":["check"],"error":"none"}"#.utf8)
        )

        XCTAssertTrue(result.reviewed)
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.suggestionsCount, 2)
        XCTAssertEqual(result.pendingCount, 1)
        XCTAssertEqual(result.pendingId, "pending1")
        XCTAssertEqual(result.actions.first?["kind"], .string("merge"))
        XCTAssertEqual(result.warnings, ["check"])
        XCTAssertEqual(result.error, "none")

        let stringCountResult = try JSONDecoder().decode(
            NapaxiSkillConsolidationReviewResult.self,
            from: Data(#"{"reviewed":true,"dry_run":false,"suggestions_count":"2","pending_count":"1"}"#.utf8)
        )
        let fractionalCountResult = try JSONDecoder().decode(
            NapaxiSkillConsolidationReviewResult.self,
            from: Data(#"{"reviewed":true,"dry_run":false,"suggestions_count":2.5,"pending_count":1.5}"#.utf8)
        )
        XCTAssertEqual(stringCountResult.suggestionsCount, 0)
        XCTAssertEqual(stringCountResult.pendingCount, 0)
        XCTAssertEqual(fractionalCountResult.suggestionsCount, 0)
        XCTAssertEqual(fractionalCountResult.pendingCount, 0)
    }

    func testEvolutionSoftFailureDecodersMirrorFlutterFacade() throws {
        let apply = try NapaxiEvolutionAPI.decodePendingEvolutionResponse(
            from: .object(["applied": .bool(true)]),
            fallbackError: "unexpected apply response"
        )
        XCTAssertEqual(apply["applied"], .bool(true))

        let reject = try NapaxiEvolutionAPI.decodePendingEvolutionResponse(
            from: .array([.string("not-object")]),
            fallbackError: "unexpected reject response"
        )
        XCTAssertEqual(reject["error"], .string("unexpected reject response"))

        let review = try NapaxiEvolutionAPI.decodeSkillConsolidationReviewResult(
            from: .object([
                "reviewed": .bool(true),
                "dry_run": .bool(false),
                "suggestions_count": .number(2),
            ])
        )
        XCTAssertTrue(review.reviewed)
        XCTAssertFalse(review.dryRun)
        XCTAssertEqual(review.suggestionsCount, 2)

        let fallbackReview = try NapaxiEvolutionAPI.decodeSkillConsolidationReviewResult(
            from: .array([.string("not-object")])
        )
        XCTAssertFalse(fallbackReview.reviewed)
        XCTAssertTrue(fallbackReview.dryRun)
        XCTAssertEqual(fallbackReview.error, "unexpected consolidation review response")
    }

    func testEvolutionStatusPreservesUnknownValues() {
        XCTAssertEqual(NapaxiEvolutionRunStatus.queued.rawValue, "queued")
        XCTAssertEqual(NapaxiEvolutionRunStatus.running.rawValue, "running")
        XCTAssertEqual(NapaxiEvolutionRunStatus.failed.rawValue, "failed")
        XCTAssertEqual(NapaxiEvolutionRunStatus(rawValue: "paused").rawValue, "paused")
    }
}
