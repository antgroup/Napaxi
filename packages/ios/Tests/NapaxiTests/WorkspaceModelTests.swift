import XCTest
@testable import Napaxi

final class WorkspaceModelTests: XCTestCase {
    func testWorkspaceAgentDefaultsMirrorFlutterFacadeSplit() {
        XCTAssertEqual(NapaxiEngine.defaultWorkspaceAgentId, "")
        XCTAssertEqual(NapaxiWorkspaceAPI.defaultAgentId, NapaxiEngine.defaultAgentId)
    }

    func testWorkspaceEngineHelpersMirrorFlutterAPISurface() {
        let readFile: (NapaxiEngine, String, String, String) throws -> NapaxiWorkspaceFile? = { engine, path, accountId, agentId in
            try engine.readWorkspaceFile(path, accountId: accountId, agentId: agentId)
        }
        let writeFile: (NapaxiEngine, String, String, String, String) throws -> Bool = { engine, path, content, accountId, agentId in
            try engine.writeWorkspaceFile(path, content, accountId: accountId, agentId: agentId)
        }
        let appendFile: (NapaxiEngine, String, String, String, String) throws -> Bool = { engine, path, content, accountId, agentId in
            try engine.appendWorkspaceFile(path, content, accountId: accountId, agentId: agentId)
        }
        let deleteFile: (NapaxiEngine, String, String, String) throws -> Bool = { engine, path, accountId, agentId in
            try engine.deleteWorkspaceFile(path, accountId: accountId, agentId: agentId)
        }
        let listFiles: (NapaxiEngine, String, String, String) throws -> [NapaxiWorkspaceEntry] = { engine, directory, accountId, agentId in
            try engine.listWorkspaceFiles(directory, accountId: accountId, agentId: agentId)
        }
        let searchMemory: (NapaxiEngine, String, Int, String, String) throws -> [NapaxiMemorySearchResult] = { engine, query, limit, accountId, agentId in
            try engine.searchMemory(query, limit: limit, accountId: accountId, agentId: agentId)
        }
        let recallSessions: (NapaxiEngine, String, Int, String, String, String) throws -> [NapaxiMemoryRecallSession] = { engine, query, limit, accountId, agentId, threadId in
            try engine.recallSessions(query, limit: limit, accountId: accountId, agentId: agentId, currentThreadId: threadId)
        }
        let rebuildRecallIndex: (NapaxiEngine, String, String) throws -> NapaxiRecallIndexStats = { engine, accountId, agentId in
            try engine.rebuildRecallIndex(accountId: accountId, agentId: agentId)
        }
        let recallIndexStats: (NapaxiEngine, String, String) throws -> NapaxiRecallIndexStats = { engine, accountId, agentId in
            try engine.recallIndexStats(accountId: accountId, agentId: agentId)
        }
        let listJournalDays: (NapaxiEngine, String, String) throws -> [NapaxiJournalDay] = { engine, accountId, agentId in
            try engine.listJournalDays(accountId: accountId, agentId: agentId)
        }
        let readJournalDay: (NapaxiEngine, String, String, String) throws -> [NapaxiJournalTurnRecord] = { engine, date, accountId, agentId in
            try engine.readJournalDay(date, accountId: accountId, agentId: agentId)
        }
        let systemPrompt: (NapaxiEngine, String, String) throws -> String = { engine, accountId, agentId in
            try engine.getSystemPrompt(accountId: accountId, agentId: agentId)
        }
        let reseed: (NapaxiEngine, String, String) throws -> Int = { engine, accountId, agentId in
            try engine.reseedWorkspace(accountId: accountId, agentId: agentId)
        }

        XCTAssertNotNil(readFile)
        XCTAssertNotNil(writeFile)
        XCTAssertNotNil(appendFile)
        XCTAssertNotNil(deleteFile)
        XCTAssertNotNil(listFiles)
        XCTAssertNotNil(searchMemory)
        XCTAssertNotNil(recallSessions)
        XCTAssertNotNil(rebuildRecallIndex)
        XCTAssertNotNil(recallIndexStats)
        XCTAssertNotNil(listJournalDays)
        XCTAssertNotNil(readJournalDay)
        XCTAssertNotNil(systemPrompt)
        XCTAssertNotNil(reseed)
    }

    func testWorkspaceSearchAliasMirrorsFlutterAPISurface() {
        let search: (NapaxiWorkspaceAPI, String) throws -> [NapaxiMemorySearchResult] = { api, query in
            try api.search(query)
        }
        let searchJSON: (NapaxiWorkspaceAPI, String, String, String, Int) throws -> NapaxiJSONValue = { api, accountId, agentId, query, limit in
            try api.searchJSON(accountId: accountId, agentId: agentId, query: query, limit: limit)
        }

        XCTAssertNotNil(search)
        XCTAssertNotNil(searchJSON)
    }

    func testWorkspaceFacadePositionalOverloadsMirrorFlutterAPISurface() {
        let writeFile: (NapaxiWorkspaceAPI, String, String, String, String) throws -> Bool = { api, path, content, accountId, agentId in
            try api.writeFile(path, content, accountId: accountId, agentId: agentId)
        }
        let appendFile: (NapaxiWorkspaceAPI, String, String, String, String) throws -> Bool = { api, path, content, accountId, agentId in
            try api.appendFile(path, content, accountId: accountId, agentId: agentId)
        }
        let listFiles: (NapaxiWorkspaceAPI, String, String, String) throws -> [NapaxiWorkspaceEntry] = { api, directory, accountId, agentId in
            try api.listFiles(directory, accountId: accountId, agentId: agentId)
        }

        XCTAssertNotNil(writeFile)
        XCTAssertNotNil(appendFile)
        XCTAssertNotNil(listFiles)
    }

    func testWorkspaceMemoryLimitsMirrorFlutterDefaultsAndClamps() {
        XCTAssertEqual(NapaxiWorkspaceAPI.defaultMemorySearchLimit, 5)
        XCTAssertEqual(NapaxiWorkspaceAPI.defaultRecallSessionLimit, 3)
        XCTAssertEqual(NapaxiWorkspaceAPI.clampedMemorySearchLimit(0), 1)
        XCTAssertEqual(NapaxiWorkspaceAPI.clampedMemorySearchLimit(21), 20)
        XCTAssertEqual(NapaxiWorkspaceAPI.clampedRecallSessionLimit(0), 1)
        XCTAssertEqual(NapaxiWorkspaceAPI.clampedRecallSessionLimit(6), 5)
    }

    func testWorkspaceFileAndEntryDecodeFlutterCompatibleFields() throws {
        let file = try JSONDecoder().decode(
            NapaxiWorkspaceFile.self,
            from: Data(#"{"path":"MEMORY.md","content":"hello","updatedAt":"2026-01-01T00:00:00Z","future":true}"#.utf8)
        )
        let entry = try JSONDecoder().decode(
            NapaxiWorkspaceEntry.self,
            from: Data(#"{"path":"daily/2026-01-01.md","isDirectory":false,"preview":"hi","updated_at":"2026-01-01T00:00:00.000Z"}"#.utf8)
        )

        XCTAssertEqual(file.path, "MEMORY.md")
        XCTAssertEqual(file.content, "hello")
        XCTAssertNotNil(file.updatedAt)
        XCTAssertEqual(file.raw["future"], .bool(true))
        XCTAssertEqual(entry.path, "daily/2026-01-01.md")
        XCTAssertEqual(entry.name, "2026-01-01.md")
        XCTAssertFalse(entry.isDirectory)
        XCTAssertEqual(entry.preview, "hi")
        XCTAssertNotNil(entry.updatedAt)
    }

    func testWorkspaceReadFileDecoderMirrorsFlutterErrorHandling() throws {
        XCTAssertNil(try NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .null))

        let file = try XCTUnwrap(NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .object([
            "path": .string("MEMORY.md"),
            "content": .string("hello"),
        ])))
        XCTAssertEqual(file.path, "MEMORY.md")
        XCTAssertEqual(file.content, "hello")

        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .object([
            "error": .string("read failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("read failed"))
        }

        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .array([]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("Expected workspace file object"))
        }

        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .object([
            "path": .number(7),
            "content": .string("hello"),
        ])))
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceFile(from: .object([
            "path": .string("MEMORY.md"),
            "content": .bool(true),
        ])))
        XCTAssertThrowsError(try WorkspaceFile.fromJson(#"{"path":"MEMORY.md","content":"hello","updatedAt":7}"#))
    }

    func testWorkspaceEntryTypedListDecoderSurfacesFlutterFactoryErrors() throws {
        let valid: [String: NapaxiJSONValue] = [
            "path": .string("daily/2026-01-01.md"),
            "isDirectory": .bool(false),
            "preview": .string("hi"),
        ]
        let entries = try NapaxiWorkspaceAPI.decodeWorkspaceEntries(from: .array([
            .string("ignored"),
            .object(valid),
        ]))
        XCTAssertEqual(entries.map(\.path), ["daily/2026-01-01.md"])

        var malformedDirectoryFlag = valid
        malformedDirectoryFlag["isDirectory"] = .string("false")
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceEntries(from: .array([.object(malformedDirectoryFlag)])))

        var malformedPreview = valid
        malformedPreview["preview"] = .number(7)
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceEntries(from: .array([.object(malformedPreview)])))

        var malformedUpdatedAt = valid
        malformedUpdatedAt["updatedAt"] = .number(1_700_000_000)
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeWorkspaceEntries(from: .array([.object(malformedUpdatedAt)])))
    }

    func testWorkspaceMapHelpersMirrorFlutterFactories() throws {
        let file = try WorkspaceFile.fromJson(
            #"{"path":"MEMORY.md","content":"hello","updatedAt":"2026-01-01T00:00:00Z","future":true}"#
        )
        let entry = WorkspaceEntry.fromMap([
            "path": .string("daily/2026-01-01.md"),
            "isDirectory": .bool(false),
            "preview": .string("hi"),
        ])
        let search = MemorySearchResult.fromMap([
            "source": .string("memory"),
            "path": .string("MEMORY.md"),
            "content": .string("hello"),
            "score": .string("0.75"),
            "is_hybrid_match": .bool(true),
            "threadId": .string(""),
            "thread_id": .string("thread"),
        ])
        let snippet = MemoryRecallSnippet.fromMap([
            "source": .string("journal"),
            "path": .string("daily/1.md"),
            "content": .string("note"),
            "score": .number(0.5),
        ])
        let session = MemoryRecallSession.fromMap([
            "threadId": .string(""),
            "thread_id": .string("thread"),
            "title": .string("Plan"),
            "summary": .string("Summary"),
            "snippets": .array([.object(snippet.toMap())]),
            "source_doc_ids": .array([
                .string("doc"),
                .number(2),
                .bool(true),
                .object(["kind": .string("memory")]),
            ]),
        ])
        let stats = RecallIndexStats.fromMap([
            "status": .string("ready"),
            "dbPath": .string(""),
            "db_path": .string("/tmp/db"),
            "schema_version": .string("2"),
            "indexed_docs": .number(3),
        ])
        let day = JournalDay.fromMap([
            "date": .string("2026-01-01"),
            "path": .string("daily/2026-01-01.md"),
            "turn_count": .string("2"),
        ])
        let turn = JournalTurnRecord.fromMap([
            "turn_id": .string("turn"),
            "thread_id": .string("thread"),
            "agent_id": .string("napaxi"),
        ])

        XCTAssertEqual(file.path, "MEMORY.md")
        XCTAssertEqual(file.toMap()["future"], .bool(true))
        XCTAssertEqual(entry.name, "2026-01-01.md")
        XCTAssertEqual(entry.toMap()["preview"], .string("hi"))
        XCTAssertEqual(search.score, 0)
        XCTAssertTrue(search.isHybridMatch)
        XCTAssertEqual(search.threadId, "thread")
        XCTAssertEqual(session.snippets.first?.content, "note")
        XCTAssertEqual(session.sourceDocIds, ["doc", "2", "true", "{kind: memory}"])
        XCTAssertEqual(stats.schemaVersion, 0)
        XCTAssertEqual(stats.indexedDocs, 3)
        XCTAssertEqual(day.turnCount, 0)
        XCTAssertEqual(turn.threadId, "thread")
        XCTAssertEqual(turn.agentId, "napaxi")
    }

    func testMemorySearchAndRecallSessionDecodeNestedFields() throws {
        let search = try JSONDecoder().decode(
            NapaxiMemorySearchResult.self,
            from: Data(#"{"source":"memory","path":"MEMORY.md","content":"hello","score":"0.75","is_hybrid_match":true,"thread_id":"t1","turn_id":"u1","created_at":"2026-01-01T00:00:00Z"}"#.utf8)
        )
        let sessionJSON = """
        {
          "thread_id": "thread",
          "title": "Plan",
          "summary": "Summary",
          "snippets": [
            {"source":"journal","path":"daily/1.md","content":"note","score":0.5,"turn_id":"turn"}
          ],
            "score": 0.9,
            "source": "recall",
            "started_at": "2026-01-01T00:00:00Z",
            "last_active_at": "2026-01-01T01:00:00Z",
            "cached": true,
            "fallback": false,
            "source_doc_ids": ["doc"],
            "systemNote": "",
            "system_note": "note"
        }
        """
        let session = try JSONDecoder().decode(NapaxiMemoryRecallSession.self, from: Data(sessionJSON.utf8))

        XCTAssertEqual(search.source, "memory")
        XCTAssertEqual(search.score, 0)
        XCTAssertTrue(search.isHybridMatch)
        XCTAssertEqual(search.threadId, "t1")
        XCTAssertEqual(search.turnId, "u1")
        XCTAssertEqual(session.threadId, "thread")
        XCTAssertEqual(session.snippets.first?.content, "note")
        XCTAssertEqual(session.snippets.first?.turnId, "turn")
        XCTAssertEqual(session.sourceDocIds, ["doc"])
        XCTAssertEqual(session.systemNote, "note")
        XCTAssertTrue(session.cached)
    }

    func testWorkspaceMemoryResultDecodersMirrorFlutterEnvelopeShapes() throws {
        let arrayResults = try NapaxiWorkspaceAPI.decodeMemorySearchResults(from: .array([
            .object([
                "source": .string("memory"),
                "path": .string("MEMORY.md"),
                "content": .string("hello"),
            ]),
        ]))
        let objectResults = try NapaxiWorkspaceAPI.decodeMemorySearchResults(from: .object([
            "results": .array([
                .object([
                    "source": .string("journal"),
                    "path": .string("daily/1.md"),
                    "content": .string("note"),
                ]),
            ]),
        ]))
        let recallResults = try NapaxiWorkspaceAPI.decodeMemoryRecallSessions(from: .object([
            "results": .array([
                .object([
                    "thread_id": .string("thread"),
                    "title": .string("Plan"),
                    "summary": .string("Summary"),
                ]),
            ]),
        ]))

        XCTAssertEqual(arrayResults.map(\.path), ["MEMORY.md"])
        XCTAssertEqual(objectResults.map(\.source), ["journal"])
        XCTAssertEqual(recallResults.map(\.threadId), ["thread"])
        XCTAssertEqual(try NapaxiWorkspaceAPI.decodeMemorySearchResults(from: .object([:])), [])
        XCTAssertEqual(try NapaxiWorkspaceAPI.decodeMemoryRecallSessions(from: .string("unexpected")), [])
    }

    func testWorkspaceMemoryResultDecodersSurfaceFlutterErrorsAndBadItems() {
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeMemorySearchResults(from: .object([
            "error": .string("search failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("search failed"))
        }
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeMemoryRecallSessions(from: .array([
            .number(7),
        ])))
    }

    func testRecallIndexStatsDecoderMirrorsFlutterErrorHandling() throws {
        let stats = try NapaxiWorkspaceAPI.decodeRecallIndexStats(from: .object([
            "status": .string("ready"),
            "schema_version": .number(2),
        ]))
        let fallback = try NapaxiWorkspaceAPI.decodeRecallIndexStats(from: .array([]))

        XCTAssertEqual(stats.status, "ready")
        XCTAssertEqual(stats.schemaVersion, 2)
        XCTAssertEqual(fallback.status, "")
        XCTAssertEqual(fallback.schemaVersion, 0)
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeRecallIndexStats(from: .object([
            "error": .string("index failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("index failed"))
        }
    }

    func testReseedAndJournalDecodersMirrorFlutterWorkspaceFacade() throws {
        let days = try NapaxiWorkspaceAPI.decodeJournalDays(from: .array([
            .object([
                "date": .string("2026-01-01"),
                "path": .string("daily/2026-01-01.md"),
            ]),
            .string("ignored"),
        ]))
        let turns = try NapaxiWorkspaceAPI.decodeJournalTurns(from: .array([
            .object([
                "turn_id": .string("turn"),
                "thread_id": .string("thread"),
            ]),
            .number(7),
        ]))

        XCTAssertEqual(try NapaxiWorkspaceAPI.decodeReseedCount(from: .object(["seeded": .number(3)])), 3)
        XCTAssertEqual(try NapaxiWorkspaceAPI.decodeReseedCount(from: .object(["error": .string("seed failed")])), 0)
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeReseedCount(from: .array([])))
        XCTAssertEqual(days.map(\.date), ["2026-01-01"])
        XCTAssertEqual(turns.map(\.turnId), ["turn"])
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeJournalDays(from: .object([
            "error": .string("journal failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("journal failed"))
        }
        XCTAssertThrowsError(try NapaxiWorkspaceAPI.decodeJournalTurns(from: .object([
            "error": .string("turns failed"),
        ]))) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidState("turns failed"))
        }
    }

    func testRecallStatsAndJournalModelsDecodeBothKeyStyles() throws {
        let stats = try JSONDecoder().decode(
            NapaxiRecallIndexStats.self,
            from: Data(#"{"status":"ready","db_path":"/tmp/db","schema_version":2,"indexed_docs":3,"memory_docs":1,"journal_docs":2,"legacy_daily_docs":4,"cached_summaries":5,"last_rebuild_at":"2026-01-01T00:00:00Z"}"#.utf8)
        )
        let day = try JSONDecoder().decode(
            NapaxiJournalDay.self,
            from: Data(#"{"date":"2026-01-01","path":"daily/2026-01-01.md","turn_count":2,"legacy":true}"#.utf8)
        )
        let turn = try JSONDecoder().decode(
            NapaxiJournalTurnRecord.self,
            from: Data(#"{"turn_id":"turn","createdAt":"2026-01-01T00:00:00Z","agent_id":"napaxi","threadId":"thread","user":"hi","assistant":"hello"}"#.utf8)
        )

        XCTAssertEqual(stats.status, "ready")
        XCTAssertEqual(stats.dbPath, "/tmp/db")
        XCTAssertEqual(stats.schemaVersion, 2)
        XCTAssertEqual(stats.indexedDocs, 3)
        XCTAssertEqual(stats.cachedSummaries, 5)
        XCTAssertNotNil(stats.lastRebuildAt)
        XCTAssertEqual(day.date, "2026-01-01")
        XCTAssertEqual(day.turnCount, 2)
        XCTAssertTrue(day.legacy)
        XCTAssertEqual(turn.turnId, "turn")
        XCTAssertEqual(turn.threadId, "thread")
        XCTAssertEqual(turn.kind, "turn")
    }

    func testWorkspacePathConstantsMatchFlutterNames() {
        XCTAssertEqual(NapaxiWorkspacePaths.soul, "SOUL.md")
        XCTAssertEqual(NapaxiWorkspacePaths.identity, "IDENTITY.md")
        XCTAssertEqual(NapaxiWorkspacePaths.agents, "AGENTS.md")
        XCTAssertEqual(NapaxiWorkspacePaths.user, "USER.md")
        XCTAssertEqual(NapaxiWorkspacePaths.memory, "MEMORY.md")
        XCTAssertEqual(NapaxiWorkspacePaths.project, "PROJECT.md")
        XCTAssertEqual(NapaxiWorkspacePaths.heartbeat, "HEARTBEAT.md")
        XCTAssertEqual(NapaxiWorkspacePaths.tools, "TOOLS.md")
        XCTAssertEqual(NapaxiWorkspacePaths.bootstrap, "BOOTSTRAP.md")
        XCTAssertEqual(NapaxiWorkspacePaths.profile, "context/profile.json")
        XCTAssertEqual(NapaxiWorkspacePaths.dailyDir, "daily/")
    }
}
