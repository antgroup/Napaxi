import XCTest
@testable import Napaxi

final class SessionModelTests: XCTestCase {
    func testHistoryPageDefaultsMirrorFlutterFacadeSplit() {
        XCTAssertEqual(NapaxiEngine.defaultHistoryPageLimit, 80)
        XCTAssertEqual(NapaxiSessionAPI.defaultHistoryPageLimit, 50)
    }

    func testSessionConvenienceOverloadsMirrorFlutterAPISurface() {
        let createWithThreadId: (NapaxiSessionAPI, String, String, String, String?) throws -> NapaxiSessionKey = { api, agentId, channelType, accountId, threadId in
            try api.create(agentId: agentId, channelType: channelType, accountId: accountId, threadId: threadId)
        }
        let createJSONWithThreadId: (NapaxiSessionAPI, String, String, String, String?) throws -> NapaxiJSONValue = { api, agentId, channelType, accountId, threadId in
            try api.createJSON(agentId: agentId, channelType: channelType, accountId: accountId, threadId: threadId)
        }
        let compactContext: (NapaxiSessionAPI, NapaxiSessionKey, String, String?) throws -> NapaxiContextStatus = { api, sessionKey, agentId, focus in
            try api.compactContext(sessionKey, agentId: agentId, focus: focus)
        }
        let contextStatus: (NapaxiSessionAPI, String, String) throws -> NapaxiContextStatus = { api, threadId, agentId in
            try api.contextStatus(threadId: threadId, agentId: agentId)
        }
        let positionalHistory: (NapaxiSessionAPI, String, String) throws -> [NapaxiChatMessage] = { api, threadId, agentId in
            try api.history(threadId, agentId: agentId)
        }
        let positionalHistoryJSON: (NapaxiSessionAPI, String, String) throws -> NapaxiJSONValue = { api, threadId, agentId in
            try api.historyJSON(threadId, agentId: agentId)
        }
        let positionalHistoryPage: (NapaxiSessionAPI, String, String, String?, Int) throws -> NapaxiHistoryPage = { api, threadId, agentId, before, limit in
            try api.historyPage(threadId, agentId: agentId, before: before, limit: limit)
        }
        let positionalHistoryPageJSON: (NapaxiSessionAPI, String, String, String?, Int) throws -> NapaxiJSONValue = { api, threadId, agentId, before, limit in
            try api.historyPageJSON(threadId, agentId: agentId, before: before, limit: limit)
        }
        let positionalContextStatus: (NapaxiSessionAPI, String, String) throws -> NapaxiContextStatus = { api, threadId, agentId in
            try api.contextStatus(threadId, agentId: agentId)
        }
        let positionalAnswerHumanRequest: (NapaxiSessionAPI, String, String) throws -> Bool = { api, requestId, response in
            try api.answerHumanRequest(requestId, response)
        }
        let engineCreateSession: (NapaxiEngine, String, String, String, String?) throws -> NapaxiSessionKey = { engine, agentId, channelType, accountId, threadId in
            try engine.createSession(agentId: agentId, channelType: channelType, accountId: accountId, threadId: threadId)
        }
        let engineListSessions: (NapaxiEngine, String, String) throws -> [NapaxiSessionInfo] = { engine, agentId, accountId in
            try engine.listSessions(agentId: agentId, accountId: accountId)
        }
        let engineDeleteSession: (NapaxiEngine, NapaxiSessionKey) throws -> Bool = { engine, sessionKey in
            try engine.deleteSession(sessionKey)
        }
        let engineClearSession: (NapaxiEngine, NapaxiSessionKey) throws -> Bool = { engine, sessionKey in
            try engine.clearSession(sessionKey)
        }
        let engineHistory: (NapaxiEngine, String, String) throws -> [NapaxiChatMessage] = { engine, threadId, agentId in
            try engine.getHistory(threadId, agentId: agentId)
        }
        let engineHistoryPage: (NapaxiEngine, String, String, String?, Int) throws -> NapaxiHistoryPage = { engine, threadId, agentId, before, limit in
            try engine.getHistoryPage(threadId, agentId: agentId, before: before, limit: limit)
        }
        let engineCompactContext: (NapaxiEngine, NapaxiSessionKey, String, String?) throws -> NapaxiContextStatus = { engine, sessionKey, agentId, focus in
            try engine.compactContext(sessionKey, agentId: agentId, focus: focus)
        }
        let engineContextStatus: (NapaxiEngine, String, String) throws -> NapaxiContextStatus = { engine, threadId, agentId in
            try engine.contextStatus(threadId, agentId: agentId)
        }

        XCTAssertNotNil(createWithThreadId)
        XCTAssertNotNil(createJSONWithThreadId)
        XCTAssertNotNil(compactContext)
        XCTAssertNotNil(contextStatus)
        XCTAssertNotNil(positionalHistory)
        XCTAssertNotNil(positionalHistoryJSON)
        XCTAssertNotNil(positionalHistoryPage)
        XCTAssertNotNil(positionalHistoryPageJSON)
        XCTAssertNotNil(positionalContextStatus)
        XCTAssertNotNil(positionalAnswerHumanRequest)
        XCTAssertNotNil(engineCreateSession)
        XCTAssertNotNil(engineListSessions)
        XCTAssertNotNil(engineDeleteSession)
        XCTAssertNotNil(engineClearSession)
        XCTAssertNotNil(engineHistory)
        XCTAssertNotNil(engineHistoryPage)
        XCTAssertNotNil(engineCompactContext)
        XCTAssertNotNil(engineContextStatus)
    }

    func testContextStatusConstructorsMirrorFlutterPublicModels() {
        let breakdown = ContextTokenBreakdown(
            systemPromptTokens: 10,
            summaryTokens: 20,
            historyTokens: 30,
            toolDescriptorTokens: 40,
            toolResultTokens: 50,
            toolCallTokens: 60,
            attachmentTokens: 70,
            imageTokens: 80,
            responseReserveTokens: 90,
            totalTokens: 450
        )
        let budget = ContextBudgetStatus(
            source: "provider",
            provider: "openai",
            model: "gpt",
            route: "warning",
            shouldCompact: true,
            estimatedPromptTokens: 120,
            contextTokenBudget: 200,
            responseReserveSource: "model",
            promptBudgetBeforeReserve: 180,
            reserveTokens: 20,
            effectiveReserveTokens: 20,
            remainingPromptBudgetTokens: 40,
            overflowTokens: 5,
            toolResultReducibleChars: 100,
            messageCount: 7,
            unwindowedMessageCount: 2,
            updatedAt: "2026-01-01T00:00:00Z"
        )
        let status = ContextStatus(
            threadId: "thread",
            engine: "compressor",
            summaryPresent: true,
            compactionCount: 1,
            tokensBefore: 300,
            tokensAfter: 120,
            estimatedTokens: 150,
            contextWindowTokens: 200,
            triggerTokens: 170,
            targetTokens: 90,
            responseReserveTokens: 20,
            usagePercent: 0.75,
            triggerRatio: 0.85,
            targetRatio: 0.45,
            displaySource: "provider",
            contextGuardStatus: "blocked",
            breakdown: breakdown,
            contextBudgetStatus: budget
        )

        XCTAssertEqual(breakdown.totalTokens, 450)
        XCTAssertEqual(budget.nativeContextWindowTokens, 0)
        XCTAssertEqual(budget.effectiveContextWindowTokens, 0)
        XCTAssertEqual(status.displayUsedTokens, 150)
        XCTAssertEqual(status.currentWindowTokens, 150)
        XCTAssertEqual(status.transcriptEstimatedTokens, 150)
        XCTAssertEqual(status.nativeContextWindowTokens, 200)
        XCTAssertEqual(status.effectiveContextWindowTokens, 200)
        XCTAssertTrue(status.isProviderBacked)
        XCTAssertTrue(status.isBudgetBlocked)
        XCTAssertEqual(status.breakdown?.historyTokens, 30)
        XCTAssertEqual(status.contextBudgetStatus?.provider, "openai")
    }

    func testChatMessageConstructorsMirrorFlutterPublicModels() {
        let attachment = ChatAttachment(
            kind: "document",
            mimeType: "text/plain",
            filename: "notes.txt",
            sandboxPath: "/workspace/notes.txt"
        )
        let tool = ToolCallInfo(
            name: "lookup",
            callId: "call-1",
            arguments: ["id": .string("42")],
            result: "ok"
        )
        let message = ChatMessage(
            role: "tool_calls",
            content: "checking",
            attachments: [attachment],
            toolCalls: [tool]
        )
        let defaultMessage = ChatMessage(role: "assistant", content: "hello")

        XCTAssertEqual(tool.name, "lookup")
        XCTAssertEqual(tool.callId, "call-1")
        XCTAssertEqual(tool.arguments?["id"], .string("42"))
        XCTAssertEqual(tool.result, "ok")
        XCTAssertFalse(tool.interrupted)
        XCTAssertFalse(tool.resultTruncated)
        XCTAssertFalse(tool.errorTruncated)
        XCTAssertFalse(tool.argumentsTruncated)
        XCTAssertTrue(message.isToolCalls)
        XCTAssertEqual(message.attachments.first?.sandboxPath, "/workspace/notes.txt")
        XCTAssertEqual(message.toolCalls?.first?.callId, "call-1")
        XCTAssertTrue(defaultMessage.isAssistant)
        XCTAssertTrue(defaultMessage.attachments.isEmpty)
        XCTAssertTrue(defaultMessage.humanOptions.isEmpty)
        XCTAssertFalse(defaultMessage.interrupted)
    }

    func testSessionKeyAndInfoDecodeFlutterCompatibleKeys() throws {
        let key = NapaxiSessionKey(channelType: "app", accountId: "user", threadId: "thread")
        let encodedKey = try NapaxiRawJSON(jsonString: key.jsonString()).value
        XCTAssertEqual(encodedKey, .object([
            "channel_type": .string("app"),
            "account_id": .string("user"),
            "thread_id": .string("thread"),
        ]))

        let infoJSON = """
        {
          "key": {"channel_type": "app", "account_id": "user", "thread_id": "thread"},
          "title": "Chat",
          "preview": "Hello",
          "message_count": 3,
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-01T00:01:00Z"
        }
        """
        let info = try JSONDecoder().decode(NapaxiSessionInfo.self, from: Data(infoJSON.utf8))

        XCTAssertEqual(info.key, key)
        XCTAssertEqual(info.title, "Chat")
        XCTAssertEqual(info.preview, "Hello")
        XCTAssertEqual(info.messageCount, 3)
        XCTAssertEqual(info.createdAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(info.updatedAt, "2026-01-01T00:01:00Z")

        let defaultedStringCount = try JSONDecoder().decode(
            NapaxiSessionInfo.self,
            from: Data(#"{"key":{"channel_type":"app","account_id":"user","thread_id":"thread"},"message_count":"3"}"#.utf8)
        )
        let defaultedFractionalCount = try JSONDecoder().decode(
            NapaxiSessionInfo.self,
            from: Data(#"{"key":{"channel_type":"app","account_id":"user","thread_id":"thread"},"message_count":3.5}"#.utf8)
        )
        XCTAssertEqual(defaultedStringCount.messageCount, 0)
        XCTAssertEqual(defaultedFractionalCount.messageCount, 0)
    }

    func testSessionModelMapHelpersMirrorFlutterFactories() throws {
        let key = try SessionKey.fromJson(#"{"channel_type":"app","thread_id":"thread"}"#)
        XCTAssertEqual(key.channelType, "app")
        XCTAssertEqual(key.accountId, "")
        XCTAssertEqual(key.threadId, "thread")
        XCTAssertEqual(key.toMap()["account_id"], .string(""))
        XCTAssertEqual(try NapaxiRawJSON(jsonString: key.toJson()).value, .object(key.toMap()))

        let info = try SessionInfo.fromJson("""
        {
          "key": {"channel_type": "app", "account_id": "user", "thread_id": "thread"},
          "title": "Chat",
          "message_count": "4"
        }
        """)
        let fractionalInfo = try SessionInfo.fromJson("""
        {
          "key": {"channel_type": "app", "account_id": "user", "thread_id": "thread"},
          "title": "Chat",
          "message_count": 4.5
        }
        """)
        XCTAssertEqual(info.key.accountId, "user")
        XCTAssertEqual(info.title, "Chat")
        XCTAssertEqual(info.messageCount, 0)
        XCTAssertEqual(fractionalInfo.messageCount, 0)

        let emptyPage = try HistoryPage.fromJson("{}")
        XCTAssertTrue(emptyPage.messages.isEmpty)
        XCTAssertFalse(emptyPage.hasMore)
        XCTAssertNil(emptyPage.nextBefore)

        let attachment = try ChatAttachment.fromMap([
            "kind": .string("document"),
            "mime_type": .string("text/plain"),
            "name": .string("notes.txt"),
            "path": .string("/tmp/notes.txt"),
        ])
        XCTAssertEqual(attachment.filename, "notes.txt")
        XCTAssertEqual(attachment.localPath, "/tmp/notes.txt")
        XCTAssertEqual(attachment.toMap()["path"], .string("/tmp/notes.txt"))

        let sandboxAttachment = try ChatAttachment.fromMap([
            "kind": .string("document"),
            "mime_type": .string("text/plain"),
            "path": .string("/workspace/notes.txt"),
        ])
        XCTAssertEqual(sandboxAttachment.sandboxPath, "/workspace/notes.txt")
        XCTAssertNil(sandboxAttachment.localPath)

        let tool = try ToolCallInfo.fromMap([
            "name": .string("lookup"),
            "tool_call_id": .string("call-1"),
            "arguments": .string(#"{"id":"42"}"#),
            "result_preview": .string("ok"),
        ])
        XCTAssertEqual(tool.name, "lookup")
        XCTAssertEqual(tool.callId, "call-1")
        XCTAssertEqual(tool.arguments?["id"], .string("42"))
        XCTAssertEqual(tool.result, "ok")
        XCTAssertTrue(tool.resultTruncated)
        XCTAssertFalse(tool.errorTruncated)
        XCTAssertFalse(tool.argumentsTruncated)

        let structuredTool = try ToolCallInfo.fromMap([
            "name": .string("structured"),
            "call_id": .string("call-2"),
            "result": .object(["ok": .bool(true)]),
            "error": .array([.string("warn"), .number(2)]),
            "arguments_truncated": .bool(true),
        ])
        XCTAssertEqual(structuredTool.result, "{ok: true}")
        XCTAssertEqual(structuredTool.error, "[warn, 2]")
        XCTAssertTrue(structuredTool.argumentsTruncated)

        let previewTool = try ToolCallInfo.fromMap([
            "name": .string("preview"),
            "call_id": .string("call-3"),
            "error_preview": .string("failed"),
            "parameters_truncated": .bool(true),
        ])
        XCTAssertEqual(previewTool.error, "failed")
        XCTAssertTrue(previewTool.errorTruncated)
        XCTAssertTrue(previewTool.argumentsTruncated)

        let encodedTool = ToolCallInfo(
            name: "encoded",
            callId: "call-4",
            arguments: ["q": .string("hello")],
            result: "done",
            interrupted: true,
            resultTruncated: true,
            errorTruncated: false,
            argumentsTruncated: true
        )
        XCTAssertEqual(encodedTool.toMap()["call_id"], .string("call-4"))
        XCTAssertEqual(encodedTool.toMap()["result_truncated"], .bool(true))
        XCTAssertEqual(encodedTool.toMap()["arguments_truncated"], .bool(true))
        XCTAssertEqual(try NapaxiRawJSON(jsonString: String(data: JSONEncoder().encode(encodedTool), encoding: .utf8)!).value, .object(encodedTool.toMap()))

        let askingHuman = try ChatMessage.fromMap([
            "role": .string("asking_human"),
            "content": .string(#"{"request_id":"h1","question":"Approve?","options":["yes","no"],"context":"ctx"}"#),
        ])
        XCTAssertTrue(askingHuman.isAskingHuman)
        XCTAssertEqual(askingHuman.humanRequestId, "h1")
        XCTAssertEqual(askingHuman.humanQuestion, "Approve?")
        XCTAssertEqual(askingHuman.humanOptions, ["yes", "no"])

        let toolCallsContent = #"{"narrative":"checking","calls":[{"name":"lookup","call_id":"c1","arguments":"{\"id\":\"42\"}","result_preview":"ok"}]}"#
        let page = try HistoryPage.fromJson("""
        {
          "messages": [
            {"role":"tool_calls","content":\(try jsonString(toolCallsContent))}
          ],
          "has_more": true,
          "next_before": "cursor"
        }
        """)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBefore, "cursor")
        XCTAssertEqual(page.messages.first?.toolCalls?.first?.arguments?["id"], .string("42"))

        let breakdown = try ContextTokenBreakdown.fromMap([
            "history_tokens": .number(70),
            "total_tokens": .string("100"),
        ])
        XCTAssertEqual(breakdown.historyTokens, 70)
        XCTAssertEqual(breakdown.totalTokens, 100)
        XCTAssertNil(try ContextTokenBreakdown.fromMapOrNull(nil))

        let budget = try ContextBudgetStatus.fromMap([
            "provider": .string("openai"),
            "model": .string("gpt"),
            "should_compact": .bool(true),
            "context_token_budget": .number(200),
            "native_context_window_tokens": .number(180),
            "native_context_window_source": .string("native"),
            "effective_context_window_tokens": .number(160),
            "effective_context_window_source": .string("provider"),
            "response_reserve_source": .string("model"),
            "provider_metadata_fetched_at": .string("2026-01-01T00:00:00Z"),
            "provider_metadata_stale": .bool(true),
            "provider_metadata_error": .string("metadata timeout"),
            "remaining_prompt_budget_tokens": .string("50"),
            "tool_result_reducible_tokens": .number(12),
            "context_guard_status": .string("warning"),
            "context_guard_reason": .string("near limit"),
        ])
        XCTAssertEqual(budget.provider, "openai")
        XCTAssertEqual(budget.model, "gpt")
        XCTAssertTrue(budget.shouldCompact)
        XCTAssertEqual(budget.nativeContextWindowTokens, 180)
        XCTAssertEqual(budget.nativeContextWindowSource, "native")
        XCTAssertEqual(budget.effectiveContextWindowTokens, 160)
        XCTAssertEqual(budget.effectiveContextWindowSource, "provider")
        XCTAssertEqual(budget.responseReserveSource, "model")
        XCTAssertEqual(budget.providerMetadataFetchedAt, "2026-01-01T00:00:00Z")
        XCTAssertTrue(budget.providerMetadataStale)
        XCTAssertEqual(budget.providerMetadataError, "metadata timeout")
        XCTAssertEqual(budget.remainingPromptBudgetTokens, 50)
        XCTAssertEqual(budget.toolResultReducibleTokens, 12)
        XCTAssertEqual(budget.contextGuardStatus, "warning")
        XCTAssertEqual(budget.contextGuardReason, "near limit")
        XCTAssertNil(try ContextBudgetStatus.fromMapOrNull(nil))

        let status = try ContextStatus.fromJson("""
        {
          "thread_id": "thread",
          "estimated_tokens": "100",
          "context_window_tokens": 200,
          "trigger_tokens": 90,
          "response_reserve_source": "model",
          "display_source": "provider",
          "native_context_window_tokens": 180,
          "native_context_window_source": "native",
          "effective_context_window_tokens": 160,
          "effective_context_window_source": "provider",
          "context_guard_status": "warning",
          "context_guard_reason": "near limit",
          "context_route": "compact",
          "overflow_tokens": 23,
          "provider_metadata_fetched_at": "2026-01-01T00:00:00Z",
          "provider_metadata_stale": true,
          "provider_metadata_error": "metadata timeout",
          "adaptive_chunk_count": 2,
          "oversized_message_count": 1,
          "protected_tail_tokens": 33,
          "overflow_retry_attempted_at": "2026-01-01T00:00:01Z",
          "overflow_retry_succeeded": false,
          "overflow_retry_reason": "tool_results",
          "overflow_retry_error": "still oversized",
          "pre_compaction_memory_flush_enabled": true,
          "pre_compaction_memory_flush_status": "flushed",
          "compaction_strategy": "rolling_summary",
          "last_compaction_duration_ms": 321,
          "breakdown": {"total_tokens": 100, "history_tokens": 70},
          "context_budget_status": {
            "provider": "openai",
            "model": "gpt",
            "should_compact": true
          }
        }
        """)
        XCTAssertEqual(status.threadId, "thread")
        XCTAssertTrue(status.isProviderBacked)
        XCTAssertFalse(status.isLegacyEstimate)
        XCTAssertTrue(status.isBudgetWarning)
        XCTAssertFalse(status.isBudgetBlocked)
        XCTAssertEqual(status.responseReserveSource, "model")
        XCTAssertEqual(status.nativeContextWindowTokens, 180)
        XCTAssertEqual(status.nativeContextWindowSource, "native")
        XCTAssertEqual(status.effectiveContextWindowTokens, 160)
        XCTAssertEqual(status.effectiveContextWindowSource, "provider")
        XCTAssertEqual(status.contextGuardReason, "near limit")
        XCTAssertEqual(status.contextRoute, "compact")
        XCTAssertEqual(status.overflowTokens, 23)
        XCTAssertEqual(status.providerMetadataFetchedAt, "2026-01-01T00:00:00Z")
        XCTAssertTrue(status.providerMetadataStale)
        XCTAssertEqual(status.providerMetadataError, "metadata timeout")
        XCTAssertEqual(status.adaptiveChunkCount, 2)
        XCTAssertEqual(status.oversizedMessageCount, 1)
        XCTAssertEqual(status.protectedTailTokens, 33)
        XCTAssertEqual(status.overflowRetryAttemptedAt, "2026-01-01T00:00:01Z")
        XCTAssertEqual(status.overflowRetrySucceeded, false)
        XCTAssertEqual(status.overflowRetryReason, "tool_results")
        XCTAssertEqual(status.overflowRetryError, "still oversized")
        XCTAssertTrue(status.preCompactionMemoryFlushEnabled)
        XCTAssertEqual(status.preCompactionMemoryFlushStatus, "flushed")
        XCTAssertEqual(status.breakdown?.historyTokens, 70)
        XCTAssertEqual(status.contextBudgetStatus?.provider, "openai")
    }

    func testSessionTypedDecodersSurfaceFlutterFactoryErrors() throws {
        let infos = try NapaxiSessionAPI.decodeSessionInfos(from: .array([
            .string("ignored"),
            .object([
                "key": .object([
                    "channel_type": .string("app"),
                    "account_id": .string("user"),
                    "thread_id": .string("thread"),
                ]),
                "title": .string("Chat"),
                "preview": .string("Hello"),
                "message_count": .number(3),
                "created_at": .string("2026-01-01T00:00:00Z"),
                "updated_at": .string("2026-01-01T00:01:00Z"),
            ]),
        ]))
        let info = try XCTUnwrap(infos.first)
        XCTAssertEqual(infos.count, 1)
        XCTAssertEqual(info.key.accountId, "user")
        XCTAssertEqual(info.messageCount, 3)
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeSessionInfos(from: .object([:])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeSessionInfos(from: .array([
            .object(["key": .string("bad")]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeSessionInfos(from: .array([
            .object(["key": .object(["thread_id": .number(1)])]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeSessionInfos(from: .array([
            .object(["message_count": .string("3")]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeSessionInfos(from: .array([
            .object(["message_count": .number(3.5)]),
        ])))

        let messages = try NapaxiSessionAPI.decodeChatMessages(from: .array([
            .number(1),
            .object([
                "role": .string("user"),
                "content": .string("hello"),
                "attachments": .array([
                    .object([
                        "kind": .string("document"),
                        "mime_type": .string("text/plain"),
                        "path": .string("/workspace/a.txt"),
                    ]),
                ]),
            ]),
        ]))
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.content, "hello")
        XCTAssertEqual(messages.first?.attachments.first?.sandboxPath, "/workspace/a.txt")
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeChatMessages(from: .object([:])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeChatMessages(from: .array([
            .object(["content": .number(1)]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeChatMessages(from: .array([
            .object(["attachments": .string("bad")]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeChatMessages(from: .array([
            .object(["attachments": .array([.string("bad")])]),
        ])))

        let emptyPage = try NapaxiSessionAPI.decodeHistoryPage(from: .object([:]))
        XCTAssertTrue(emptyPage.messages.isEmpty)
        XCTAssertFalse(emptyPage.hasMore)

        let page = try NapaxiSessionAPI.decodeHistoryPage(from: .object([
            "messages": .array([
                .object(["role": .string("assistant"), "content": .string("done")]),
            ]),
            "has_more": .bool(true),
            "next_before": .string("cursor"),
        ]))
        XCTAssertEqual(page.messages.count, 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBefore, "cursor")
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeHistoryPage(from: .array([])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeHistoryPage(from: .object([
            "messages": .string("bad"),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeHistoryPage(from: .object([
            "messages": .array([.string("bad")]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeHistoryPage(from: .object([
            "has_more": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeHistoryPage(from: .object([
            "next_before": .number(1),
        ])))

        let status = try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "thread_id": .string("thread"),
            "summary_present": .bool(true),
            "estimated_tokens": .string("100"),
            "context_window_tokens": .number(200),
            "usage_percent": .string("50.5"),
            "display_source": .string("provider"),
            "provider_metadata_stale": .bool(true),
            "context_budget_status": .object([
                "provider": .string("openai"),
                "should_compact": .bool(true),
            ]),
        ]))
        XCTAssertEqual(status.threadId, "thread")
        XCTAssertTrue(status.summaryPresent)
        XCTAssertEqual(status.estimatedTokens, 100)
        XCTAssertEqual(status.contextWindowTokens, 200)
        XCTAssertEqual(status.usagePercent, 50.5)
        XCTAssertTrue(status.providerMetadataStale)
        XCTAssertEqual(status.contextBudgetStatus?.provider, "openai")
        XCTAssertTrue(status.contextBudgetStatus?.shouldCompact ?? false)
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .string("bad")))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "thread_id": .number(1),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "summary_present": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "provider_metadata_stale": .string("true"),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "context_budget_status": .object([
                "provider": .number(1),
            ]),
        ])))
        XCTAssertThrowsError(try NapaxiSessionAPI.decodeContextStatus(from: .object([
            "context_budget_status": .object([
                "should_compact": .string("true"),
            ]),
        ])))
    }

    func testHistoryPageAndChatMessageDecodeToolCallsAndHitl() throws {
        let toolCallsContent = #"{"narrative":"checking","calls":[{"name":"lookup","call_id":"c1","arguments":{"id":"42"},"result_preview":"ok"}]}"#
        let askingHumanContent = #"{"request_id":"h1","question":"Approve?","options":["yes","no"],"context":"ctx"}"#
        let pageJSON = """
        {
          "messages": [
            {"role":"tool_calls","content":\(try jsonString(toolCallsContent)),"created_at":"now"},
            {"role":"asking_human","content":\(try jsonString(askingHumanContent))},
            {"role":"user","content":"file","attachments":[{"kind":"document","mime_type":"text/plain","path":"/workspace/a.txt"}]}
          ],
          "has_more": true,
          "next_before": "cursor"
        }
        """

        let page = try JSONDecoder().decode(NapaxiHistoryPage.self, from: Data(pageJSON.utf8))

        XCTAssertEqual(page.messages.count, 3)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextBefore, "cursor")
        XCTAssertTrue(page.messages[0].isToolCalls)
        XCTAssertEqual(page.messages[0].thinkingContent, "checking")
        XCTAssertEqual(page.messages[0].toolCalls?.first?.name, "lookup")
        XCTAssertEqual(page.messages[0].toolCalls?.first?.arguments?["id"], .string("42"))
        XCTAssertTrue(page.messages[1].isAskingHuman)
        XCTAssertEqual(page.messages[1].humanRequestId, "h1")
        XCTAssertEqual(page.messages[1].humanOptions, ["yes", "no"])
        XCTAssertEqual(page.messages[2].attachments.first?.sandboxPath, "/workspace/a.txt")
        XCTAssertNil(page.messages[2].attachments.first?.localPath)
    }

    func testMalformedToolCallsContentKeepsMessageLikeFlutter() throws {
        let malformedCallsContent = #"{"narrative":"checking","calls":[7]}"#
        let message = try ChatMessage.fromMap([
            "role": .string("tool_calls"),
            "content": .string(malformedCallsContent),
        ])

        XCTAssertTrue(message.isToolCalls)
        XCTAssertEqual(message.thinkingContent, "checking")
        XCTAssertNil(message.toolCalls)
    }

    func testContextStatusDecodesDefaultsAndNestedBudget() throws {
        let json = """
        {
          "thread_id": "thread",
          "estimated_tokens": "100",
          "context_window_tokens": 200,
          "trigger_tokens": 90,
          "response_reserve_source": "model",
          "display_source": "provider",
          "native_context_window_tokens": 180,
          "native_context_window_source": "native",
          "effective_context_window_tokens": 160,
          "effective_context_window_source": "provider",
          "context_guard_status": "blocked",
          "context_guard_reason": "overflow",
          "overflow_tokens": 42,
          "provider_metadata_fetched_at": "2026-01-01T00:00:00Z",
          "provider_metadata_stale": true,
          "provider_metadata_error": "metadata timeout",
          "adaptive_chunk_count": 2,
          "oversized_message_count": 1,
          "protected_tail_tokens": 33,
          "overflow_retry_attempted_at": "2026-01-01T00:00:01Z",
          "overflow_retry_succeeded": true,
          "overflow_retry_reason": "compaction",
          "pre_compaction_memory_flush_enabled": true,
          "pre_compaction_memory_flush_status": "flushed",
          "compaction_strategy": "rolling_summary",
          "last_compaction_duration_ms": 321,
          "breakdown": {"total_tokens": 100, "history_tokens": 70},
          "context_budget_status": {
            "provider": "openai",
            "model": "gpt",
            "should_compact": true,
            "context_token_budget": 200,
            "native_context_window_tokens": 180,
            "effective_context_window_tokens": 160,
            "response_reserve_source": "model",
            "remaining_prompt_budget_tokens": 50,
            "tool_result_reducible_tokens": 12,
            "context_guard_status": "blocked",
            "context_guard_reason": "overflow",
            "route": "block",
            "provider_metadata_fetched_at": "2026-01-01T00:00:00Z",
            "provider_metadata_stale": true,
            "provider_metadata_error": "metadata timeout"
          }
        }
        """

        let status = try JSONDecoder().decode(NapaxiContextStatus.self, from: Data(json.utf8))

        XCTAssertEqual(status.threadId, "thread")
        XCTAssertEqual(status.engine, "compressor")
        XCTAssertEqual(status.estimatedTokens, 100)
        XCTAssertEqual(status.displayUsedTokens, 100)
        XCTAssertEqual(status.currentWindowTokens, 100)
        XCTAssertTrue(status.isNearTrigger)
        XCTAssertTrue(status.isBudgetBlocked)
        XCTAssertFalse(status.isBudgetWarning)
        XCTAssertEqual(status.usageFraction, 0.5)
        XCTAssertEqual(status.responseReserveSource, "model")
        XCTAssertEqual(status.nativeContextWindowTokens, 180)
        XCTAssertEqual(status.effectiveContextWindowTokens, 160)
        XCTAssertEqual(status.contextRoute, "block")
        XCTAssertEqual(status.overflowTokens, 42)
        XCTAssertEqual(status.providerMetadataFetchedAt, "2026-01-01T00:00:00Z")
        XCTAssertTrue(status.providerMetadataStale)
        XCTAssertEqual(status.providerMetadataError, "metadata timeout")
        XCTAssertEqual(status.adaptiveChunkCount, 2)
        XCTAssertEqual(status.oversizedMessageCount, 1)
        XCTAssertEqual(status.protectedTailTokens, 33)
        XCTAssertEqual(status.overflowRetryAttemptedAt, "2026-01-01T00:00:01Z")
        XCTAssertEqual(status.overflowRetrySucceeded, true)
        XCTAssertEqual(status.overflowRetryReason, "compaction")
        XCTAssertNil(status.overflowRetryError)
        XCTAssertTrue(status.preCompactionMemoryFlushEnabled)
        XCTAssertEqual(status.preCompactionMemoryFlushStatus, "flushed")
        XCTAssertEqual(status.breakdown?.historyTokens, 70)
        XCTAssertEqual(status.breakdown?.totalTokens, 100)
        XCTAssertEqual(status.contextBudgetStatus?.provider, "openai")
        XCTAssertEqual(status.contextBudgetStatus?.model, "gpt")
        XCTAssertEqual(status.contextBudgetStatus?.shouldCompact, true)
        XCTAssertEqual(status.contextBudgetStatus?.nativeContextWindowTokens, 180)
        XCTAssertEqual(status.contextBudgetStatus?.effectiveContextWindowTokens, 160)
        XCTAssertEqual(status.contextBudgetStatus?.responseReserveSource, "model")
        XCTAssertEqual(status.contextBudgetStatus?.remainingPromptBudgetTokens, 50)
        XCTAssertEqual(status.contextBudgetStatus?.toolResultReducibleTokens, 12)
        XCTAssertEqual(status.contextBudgetStatus?.contextGuardStatus, "blocked")
        XCTAssertEqual(status.contextBudgetStatus?.contextGuardReason, "overflow")
        XCTAssertEqual(status.contextBudgetStatus?.providerMetadataFetchedAt, "2026-01-01T00:00:00Z")
        XCTAssertEqual(status.contextBudgetStatus?.providerMetadataStale, true)
        XCTAssertEqual(status.contextBudgetStatus?.providerMetadataError, "metadata timeout")
        XCTAssertEqual(status.compactionStrategy, "rolling_summary")
        XCTAssertEqual(status.lastCompactionDurationMs, 321)
    }
}

private func jsonString(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
    return String(data: data, encoding: .utf8) ?? "\"\""
}
