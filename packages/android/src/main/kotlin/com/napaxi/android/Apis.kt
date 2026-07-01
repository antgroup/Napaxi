package com.napaxi.android

import android.content.ClipData
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URLEncoder
import java.net.URL

public class ChatApi internal constructor(private val engine: NapaxiEngine) {
    public fun send(
        message: String,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = engine.send(message, attachments, maxIterations)

    public fun sendToSession(
        session: SessionKey,
        message: String,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
        sandboxPaths: List<String>? = null,
    ): Flow<ChatEvent> = engine.sendToSessionFlow(session, message, agentId, attachments, maxIterations, sandboxPaths)
}

public class SessionApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun create(
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
        channelType: String = "app",
        accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID,
        threadId: String? = null,
    ): SessionKey = withContext(Dispatchers.IO) {
        engine.createSession(agentId, channelType, accountId, threadId)
    }

    public suspend fun list(
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
        accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID,
    ): List<SessionInfo> = withContext(Dispatchers.IO) {
        engine.listSessions(agentId, accountId)
    }

    public suspend fun delete(
        sessionKey: SessionKey,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): Boolean = engine.deleteSession(sessionKey, agentId)

    public suspend fun clear(
        sessionKey: SessionKey,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): Boolean = engine.clearSession(sessionKey, agentId)

    public suspend fun cancel(
        sessionKey: SessionKey,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): Boolean = withContext(Dispatchers.IO) {
        engine.cancelSession(sessionKey, agentId)
    }

    public suspend fun answerHumanRequest(requestId: String, response: String): Boolean =
        engine.answerHumanRequest(requestId, response)

    public suspend fun history(threadId: String, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<ChatMessage> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.getHistoryJson(threadId, agentId), "messages").map {
                ChatMessage(it.toString())
            }
        }

    public suspend fun historyPage(
        threadId: String,
        before: String? = null,
        limit: Long = 50,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): HistoryPage = withContext(Dispatchers.IO) {
        HistoryPage(
            engine.bridge(
                "session.history_page",
                JSONObject()
                    .put("config_json", engine.config.toJson())
                    .put("agent_id", agentId)
                    .put("thread_id", threadId)
                    .put("before", before)
                    .put("limit", limit),
            ),
        )
    }

    public suspend fun compactContext(
        sessionKey: SessionKey,
        focus: String? = null,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): ContextStatus = withContext(Dispatchers.IO) {
        ContextStatus(
            engine.bridge(
                "session.compact_context",
                JSONObject()
                    .put("config_json", engine.config.toJson())
                    .put("agent_id", agentId)
                    .put("session_key_json", sessionKey.toJson())
                    .put("focus", focus),
            ),
        )
    }

    public suspend fun contextStatus(
        threadId: String,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): ContextStatus = withContext(Dispatchers.IO) {
        ContextStatus(
            engine.bridge(
                "session.context_status",
                JSONObject()
                    .put("config_json", engine.config.toJson())
                    .put("agent_id", agentId)
                    .put("thread_id", threadId),
            ),
        )
    }

    public suspend fun injectMessage(
        sessionKey: SessionKey,
        message: String,
        attachments: List<McAttachment> = emptyList(),
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
    ): Boolean = engine.injectMessage(sessionKey, message, attachments, agentId)

    public suspend fun retractInjectedMessage(sessionKey: SessionKey, message: String): Boolean =
        engine.retractInjectedMessage(sessionKey, message)

    public fun saveAttachmentMetadata(
        threadId: String,
        userMsgIndex: Int,
        attachments: List<ChatAttachment>,
    ): Boolean = engine.saveAttachmentMetadata(threadId, userMsgIndex, attachments)
}

public class SessionRunApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun list(
        agentId: String? = null,
        threadId: String? = null,
        status: SessionRunRecordStatus? = null,
        limit: Long = 100,
        offset: Long = 0,
    ): List<SessionRunRecord> =
        listWithFilter(
            JSONObject()
                .apply {
                    agentId?.let { put("agentId", it) }
                    threadId?.let { put("threadId", it) }
                    status?.takeIf { it != SessionRunRecordStatus.Unknown }?.let { put("status", it.wireName) }
                }
                .toString(),
            limit,
            offset,
        )

    public suspend fun listWithFilter(filterJson: String = "{}", limit: Long = 100, offset: Long = 0): List<SessionRunRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "session_runs.list",
                    JSONObject().put("filter_json", filterJson).put("limit", limit).put("offset", offset),
                ),
                "runs",
            ).map { SessionRunRecord.fromJsonObject(it) }
        }

    public suspend fun get(runId: String): SessionRunRecord? =
        withContext(Dispatchers.IO) {
            SessionRunRecord.fromJsonOrNull(engine.bridge("session_runs.get", JSONObject().put("run_id", runId)))
        }

    public suspend fun active(): List<SessionRunRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("session_runs.active"), "runs").map { SessionRunRecord.fromJsonObject(it) }
        }
}

public class AgentApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun getOrCreate(agentId: String, config: LlmConfig? = null): AgentHandle =
        withContext(Dispatchers.IO) {
            engine.getOrCreateAgent(agentId, config) ?: AgentHandle(agentId, "{}")
        }

    public fun send(
        agentId: String,
        session: SessionKey,
        message: String,
        config: LlmConfig? = null,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = engine.agentSend(agentId, session, message, config, maxIterations)

    public fun send(
        agent: AgentHandle,
        session: SessionKey,
        message: String,
        config: LlmConfig? = null,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = engine.agentSend(agent, session, message, config, maxIterations)

    public suspend fun list(): List<String> = withContext(Dispatchers.IO) { engine.listAgents() }

    public suspend fun delete(agentId: String): Boolean =
        withContext(Dispatchers.IO) { engine.bridgeBool("agent.delete", JSONObject().put("agent_id", agentId)) }

    public suspend fun createDefinition(definitionJson: String): AgentDefinition =
        withContext(Dispatchers.IO) {
            AgentDefinition(engine.bridge("agent_defs.create", JSONObject().put("def_json", definitionJson)))
        }

    public suspend fun createDefinition(definition: AgentDefinition): AgentDefinition =
        createDefinition(definition.toJson())

    public suspend fun listDefinitions(): List<AgentDefinition> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("agent_defs.list"), "definitions").map {
                AgentDefinition(it.toString())
            }
        }

    public suspend fun getDefinition(defId: String): AgentDefinition? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("agent_defs.get", JSONObject().put("def_id", defId))
            if (raw.isBlank() || raw == "null") null else AgentDefinition(raw)
        }

    public suspend fun updateDefinition(definitionJson: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("agent_defs.update", JSONObject().put("def_json", definitionJson))
        }

    public suspend fun updateDefinition(definition: AgentDefinition): Boolean =
        updateDefinition(definition.toJson())

    public suspend fun deleteDefinition(defId: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("agent_defs.delete", JSONObject().put("def_id", defId))
        }

    public suspend fun importMarkdown(content: String): AgentDefinition =
        withContext(Dispatchers.IO) {
            AgentDefinition(engine.bridge("agent_defs.import_md", JSONObject().put("content", content)))
        }

    public suspend fun listAvailableTools(): List<ToolInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("agent_defs.list_available_tools"), "tools").map {
                ToolInfo(it.toString())
            }
        }

    public suspend fun createFromDefinition(defId: String, config: LlmConfig? = null): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeLong(
                "agent_defs.create_agent",
                JSONObject().put("def_id", defId).put("config_json", (config ?: engine.config).toJson()),
            ) != 0L
        }
}

public class ToolApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun updateCustomTools(tools: List<CustomToolDef>): Boolean =
        withContext(Dispatchers.IO) { engine.updateCustomTools(tools) }

    public fun startRequestListener() {
        engine.startToolRequestListener()
    }

    public suspend fun availableTools(): List<ToolInfo> = engine.agents.listAvailableTools()

    public suspend fun platformToolDescriptors(): List<ToolInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("tools.platform_descriptors", handle = 0L), "tools").map {
                ToolInfo(it.toString())
            }
        }

    public suspend fun isPlatformTool(name: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("tools.is_platform_tool", JSONObject().put("name", name), handle = 0L)
        }

    public suspend fun browserToolDescriptors(): List<CustomToolDef> =
        withContext(Dispatchers.IO) { BrowserToolProvider.getToolDefinitions() }

    public suspend fun isBrowserTool(name: String): Boolean =
        withContext(Dispatchers.IO) { BrowserToolProvider.isBrowserTool(name) }
}

public class CapabilityApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun definitions(): List<NapaxiCapabilityDefinition> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("capability.definitions", handle = 0L), "definitions").map {
                NapaxiCapabilityDefinition(it.toString())
            }
        }

    public suspend fun listDefinitions(): List<NapaxiCapabilityDefinition> = definitions()

    public suspend fun status(
        profile: NapaxiCapabilityProfile? = null,
        selection: NapaxiCapabilitySelection? = null,
    ): List<NapaxiCapabilityStatus> = withContext(Dispatchers.IO) {
        jsonArrayOfObjects(
            engine.bridge(
                "capability.status",
                JSONObject()
                    .put("profile_json", (profile ?: engine.defaultCapabilityProfile()).toJson())
                    .put("selection_json", (selection ?: engine.defaultCapabilitySelection()).toJson()),
            ),
            "statuses",
        ).map { NapaxiCapabilityStatus(it.toString()) }
    }

    public suspend fun listStatuses(
        profile: NapaxiCapabilityProfile? = null,
        selection: NapaxiCapabilitySelection? = null,
    ): List<NapaxiCapabilityStatus> = status(profile, selection)

    public suspend fun listScenarioPacks(): List<NapaxiScenarioPack> =
        withContext(Dispatchers.IO) {
            decodeScenarioPacks(engine.bridge("capability.scenarios"))
        }

    public suspend fun installScenarioPack(pack: NapaxiScenarioPack): NapaxiScenarioPackInstallResult? =
        installScenarioPackJson(pack.toJson())

    public suspend fun installScenarioPackJson(packJson: String): NapaxiScenarioPackInstallResult? =
        withContext(Dispatchers.IO) {
            decodeScenarioPackInstallResult(
                engine.bridge("capability.install_scenario", JSONObject().put("pack_json", packJson)),
            )
        }

    public suspend fun removeScenarioPack(scenarioId: String): NapaxiScenarioPackRemovalResult? =
        withContext(Dispatchers.IO) {
            decodeScenarioPackRemovalResult(
                engine.bridge("capability.remove_scenario", JSONObject().put("scenario_id", scenarioId)),
            )
        }

    public suspend fun listScenarioStatuses(
        profile: NapaxiCapabilityProfile? = null,
        selection: NapaxiCapabilitySelection? = null,
    ): List<NapaxiScenarioStatus> = withContext(Dispatchers.IO) {
        decodeScenarioStatuses(
            engine.bridge(
                "capability.scenario_status",
                JSONObject()
                    .put("profile_json", (profile ?: engine.defaultCapabilityProfile()).toJson())
                    .put("selection_json", (selection ?: engine.defaultCapabilitySelection()).toJson()),
            ),
        )
    }

    public suspend fun resolveScenario(
        scenarioId: String,
        profile: NapaxiCapabilityProfile? = null,
        selection: NapaxiCapabilitySelection? = null,
    ): NapaxiScenarioResolution? = withContext(Dispatchers.IO) {
        decodeScenarioResolution(
            engine.bridge(
                "capability.scenario",
                JSONObject()
                    .put("scenario_id", scenarioId)
                    .put("profile_json", (profile ?: engine.defaultCapabilityProfile()).toJson())
                    .put("selection_json", (selection ?: engine.defaultCapabilitySelection()).toJson()),
            ),
        )
    }

    public suspend fun providerCapabilityId(provider: String): String =
        withContext(Dispatchers.IO) {
            engine.bridge("capability.provider_id", JSONObject().put("provider", provider), handle = 0L)
        }

    public suspend fun agentEngineCapabilityId(engineId: String): String =
        withContext(Dispatchers.IO) {
            engine.bridge("capability.agent_engine_id", JSONObject().put("engine_id", engineId), handle = 0L)
        }

    public suspend fun toolCapabilityId(toolName: String): String =
        withContext(Dispatchers.IO) {
            engine.bridge("capability.tool_id", JSONObject().put("tool_name", toolName), handle = 0L)
        }
}

public class ChannelApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun list(): List<NapaxiChannelRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("channel.list"), "channels").map {
                NapaxiChannelRecord(it.toString())
            }
        }

    public suspend fun register(registration: NapaxiChannelRegistration): Boolean =
        registerJson(registration.toJson())

    public suspend fun registerJson(configJson: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("channel.register", JSONObject().put("config_json", configJson))
        }

    public suspend fun unregister(channelName: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("channel.unregister", JSONObject().put("channel_name", channelName))
        }

    public suspend fun submitInbound(message: NapaxiChannelInboundMessage): NapaxiChannelAcceptedReceipt =
        submitInboundJson(message.toJson())

    public suspend fun submitInboundJson(envelopeJson: String): NapaxiChannelAcceptedReceipt =
        withContext(Dispatchers.IO) {
            NapaxiChannelAcceptedReceipt.fromJson(
                engine.bridge("channel.submit_inbound", JSONObject().put("envelope_json", envelopeJson)),
            )
        }

    public suspend fun takeInbound(channelName: String, limit: Int = 20): List<NapaxiChannelInboundMessage> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "channel.take_inbound",
                    JSONObject().put("channel_name", channelName).put("limit", limit),
                ),
                "inbound",
            ).map { NapaxiChannelInboundMessage.fromJsonObject(it) }
        }

    public suspend fun ackInbound(inboundId: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("channel.ack_inbound", JSONObject().put("inbound_id", inboundId))
        }

    public suspend fun enqueueOutbound(message: NapaxiChannelOutboundMessage): NapaxiChannelAcceptedReceipt =
        enqueueOutboundJson(message.toJson())

    public suspend fun enqueueOutboundJson(outboundJson: String): NapaxiChannelAcceptedReceipt =
        withContext(Dispatchers.IO) {
            NapaxiChannelAcceptedReceipt.fromJson(
                engine.bridge("channel.enqueue_outbound", JSONObject().put("outbound_json", outboundJson)),
            )
        }

    public suspend fun replyInbound(inboundId: String, message: NapaxiChannelOutboundMessage): NapaxiChannelAcceptedReceipt =
        replyInboundJson(inboundId, message.toJson())

    public suspend fun replyInboundJson(inboundId: String, replyJson: String): NapaxiChannelAcceptedReceipt =
        withContext(Dispatchers.IO) {
            NapaxiChannelAcceptedReceipt.fromJson(
                engine.bridge(
                    "channel.reply_inbound",
                    JSONObject().put("inbound_id", inboundId).put("reply_json", replyJson),
                ),
            )
        }

    public suspend fun leaseOutbound(
        channelName: String,
        accountId: String? = null,
        limit: Int = 20,
    ): List<NapaxiChannelOutboundMessage> =
        withContext(Dispatchers.IO) {
            val payload = JSONObject().put("channel_name", channelName).put("limit", limit)
            accountId?.let { payload.put("account_id", it) }
            jsonArrayOfObjects(
                engine.bridge("channel.lease_outbound", payload),
                "outbound",
            ).map { NapaxiChannelOutboundMessage.fromJsonObject(it) }
        }

    public suspend fun ackOutbound(outboundId: String, receipt: JSONObject = JSONObject()): Boolean =
        ackOutboundJson(outboundId, receipt.toString())

    public suspend fun ackOutboundJson(outboundId: String, receiptJson: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool(
                "channel.ack_outbound",
                JSONObject().put("outbound_id", outboundId).put("receipt_json", receiptJson),
            )
        }

    public suspend fun failOutbound(outboundId: String, error: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool(
                "channel.fail_outbound",
                JSONObject().put("outbound_id", outboundId).put("error", error),
            )
        }
}

public class ChannelAgentApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun registerRoute(route: NapaxiChannelAgentRoute): NapaxiChannelAgentRoute =
        registerRouteJson(route.toJson())

    public suspend fun registerRouteJson(routeJson: String): NapaxiChannelAgentRoute =
        withContext(Dispatchers.IO) {
            NapaxiChannelAgentRoute.fromJson(
                engine.bridge("channel_agent.register_route", JSONObject().put("route_json", routeJson)),
            )
        }

    public suspend fun listRoutes(channelName: String? = null): List<NapaxiChannelAgentRoute> =
        withContext(Dispatchers.IO) {
            val payload = JSONObject()
            channelName?.let { payload.put("channel_name", it) }
            jsonArrayOfObjects(
                engine.bridge("channel_agent.list_routes", payload),
                "routes",
            ).map { NapaxiChannelAgentRoute.fromJsonObject(it) }
        }

    public suspend fun removeRoute(routeId: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("channel_agent.remove_route", JSONObject().put("route_id", routeId))
        }

    public suspend fun resolveRouteJson(
        bridgeConfigJson: String,
        inboundJson: String,
    ): JSONObject = withContext(Dispatchers.IO) {
        JSONObject(
            engine.bridge(
                "channel_agent.resolve_route",
                JSONObject()
                    .put("bridge_config_json", bridgeConfigJson)
                    .put("inbound_json", inboundJson),
            ).ifBlank { "{}" },
        )
    }

    public suspend fun status(channelName: String? = null): NapaxiChannelAgentStatus =
        withContext(Dispatchers.IO) {
            val payload = JSONObject()
            channelName?.let { payload.put("channel_name", it) }
            NapaxiChannelAgentStatus.fromJson(engine.bridge("channel_agent.status", payload))
        }

    public fun streamPump(): Nothing {
        throw UnsupportedOperationException(
            "Android ChannelAgent streamPump is unavailable in v1; use Flutter bridge or call core route/status plus channel queue APIs.",
        )
    }
}

public class QqBotProtocolApi internal constructor(private val engine: NapaxiEngine) {
    public fun buildOutboundPayload(
        messageJson: String,
        markdownEndpointKindsJson: String = "",
    ): String = engine.bridge(
        "channel_qqbot.build_outbound_payload",
        JSONObject()
            .put("message_json", messageJson)
            .put("markdown_endpoint_kinds_json", markdownEndpointKindsJson),
        handle = 0L,
    )

    public fun buildOutboundPayloadPlain(messageJson: String): String =
        engine.bridge(
            "channel_qqbot.build_outbound_payload_plain",
            JSONObject().put("message_json", messageJson),
            handle = 0L,
        )

    public fun shouldFallbackFromMarkdown(status: Int): Boolean =
        engine.bridgeBool(
            "channel_qqbot.should_fallback_from_markdown",
            JSONObject().put("status", status),
            handle = 0L,
        )

    public fun outboundEndpointPath(peerKind: String, peerId: String): String =
        engine.bridge(
            "channel_qqbot.outbound_endpoint_path",
            JSONObject().put("peer_kind", peerKind).put("peer_id", peerId),
            handle = 0L,
        )

    public fun apiBase(sandbox: Boolean): String =
        engine.bridge(
            "channel_qqbot.api_base",
            JSONObject().put("sandbox", sandbox),
            handle = 0L,
        )

    public fun isMessageEvent(eventType: String): Boolean =
        engine.bridgeBool(
            "channel_qqbot.is_message_event",
            JSONObject().put("event_type", eventType),
            handle = 0L,
        )

    public fun normalizeInbound(eventType: String, dataJson: String): String =
        engine.bridge(
            "channel_qqbot.normalize_inbound",
            JSONObject().put("event_type", eventType).put("data_json", dataJson),
            handle = 0L,
        )

    public fun gatewayStep(stateJson: String, eventJson: String): String =
        engine.bridge(
            "channel_qqbot.gateway_step",
            JSONObject().put("state_json", stateJson).put("event_json", eventJson),
            handle = 0L,
        )
}

public class WorkspaceApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun readFile(path: String, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): WorkspaceFile? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("workspace.read", JSONObject().scope(accountId, agentId).put("path", path))
            if (raw.isBlank() || raw == "null") null else WorkspaceFile(raw)
        }

    public suspend fun writeFile(path: String, content: String, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("workspace.write", JSONObject().scope(accountId, agentId).put("path", path).put("content", content))
        }

    public suspend fun appendFile(path: String, content: String, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("workspace.append", JSONObject().scope(accountId, agentId).put("path", path).put("content", content))
        }

    public suspend fun deleteFile(path: String, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("workspace.delete", JSONObject().scope(accountId, agentId).put("path", path))
        }

    public suspend fun listFiles(directory: String = "", accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<WorkspaceEntry> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge("workspace.list", JSONObject().scope(accountId, agentId).put("directory", directory)),
                "entries",
            ).map { WorkspaceEntry(it.toString()) }
        }

    public suspend fun search(query: String, limit: Int = 5, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<MemorySearchResult> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge("workspace.search_memory", JSONObject().scope(accountId, agentId).put("query", query).put("limit", limit)),
                "results",
            ).map { MemorySearchResult(it.toString()) }
        }

    public suspend fun recallSessions(
        query: String,
        limit: Int = 3,
        accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID,
        agentId: String = NapaxiEngine.DEFAULT_AGENT_ID,
        currentThreadId: String = "",
    ): List<MemoryRecallSession> =
        recallSessionsForThread(
            currentThreadId = currentThreadId,
            query = query,
            limit = limit,
            accountId = accountId,
            agentId = agentId,
        )

    public suspend fun recallSessionsForThread(currentThreadId: String, query: String, limit: Int = 5, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<MemoryRecallSession> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "workspace.recall_sessions",
                    JSONObject().scope(accountId, agentId)
                        .put("config_json", engine.config.toJson())
                        .put("current_thread_id", currentThreadId)
                        .put("query", query)
                        .put("limit", limit),
                ),
                "sessions",
            ).map { MemoryRecallSession(it.toString()) }
        }

    public suspend fun rebuildRecallIndex(accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): RecallIndexStats =
        withContext(Dispatchers.IO) {
            RecallIndexStats(engine.bridge("workspace.rebuild_recall_index", JSONObject().scope(accountId, agentId)))
        }

    public suspend fun recallIndexStats(accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): RecallIndexStats =
        withContext(Dispatchers.IO) {
            RecallIndexStats(engine.bridge("workspace.recall_index_stats", JSONObject().scope(accountId, agentId)))
        }

    public suspend fun listJournalDays(accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<JournalDay> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("workspace.list_journal_days", JSONObject().scope(accountId, agentId)), "days").map {
                JournalDay(it.toString())
            }
        }

    public suspend fun readJournalDay(date: String, accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): List<JournalTurnRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("workspace.read_journal_day", JSONObject().scope(accountId, agentId).put("date", date)), "turns").map {
                JournalTurnRecord(it.toString())
            }
        }

    public suspend fun systemPrompt(accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): String =
        withContext(Dispatchers.IO) {
            engine.bridge("workspace.system_prompt", JSONObject().scope(accountId, agentId))
        }

    public suspend fun reseed(accountId: String = NapaxiEngine.DEFAULT_ACCOUNT_ID, agentId: String = NapaxiEngine.DEFAULT_AGENT_ID): Int =
        withContext(Dispatchers.IO) {
            JSONObject(engine.bridge("workspace.reseed", JSONObject().scope(accountId, agentId))).optInt("count", 0)
        }
}

public class SkillApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun list(agentId: String = ""): List<SkillInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("skill.list", JSONObject().put("agent_id", agentId)), "skills").map {
                SkillInfo(it.toString())
            }
        }

    public suspend fun get(skillName: String, agentId: String = ""): SkillInfo? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge(
                "skill.get",
                JSONObject().put("agent_id", agentId).put("skill_name", skillName),
            )
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else SkillInfo(raw)
        }

    public suspend fun status(agentId: String = ""): SkillStatusReport =
        withContext(Dispatchers.IO) {
            SkillStatusReport(engine.bridge("skill.status", JSONObject().put("agent_id", agentId)))
        }

    public suspend fun sources(agentId: String = ""): SkillSourceReport =
        withContext(Dispatchers.IO) {
            SkillSourceReport(engine.bridge("skill.sources", JSONObject().put("agent_id", agentId)))
        }

    public suspend fun recordSourceChanged(sourceId: String, agentId: String = ""): SkillRefreshResult =
        withContext(Dispatchers.IO) {
            SkillRefreshResult(
                engine.bridge(
                    "skill.record_source_changed",
                    JSONObject().put("agent_id", agentId).put("source_id", sourceId),
                ),
            )
        }

    public suspend fun getStatus(skillName: String, agentId: String = ""): SkillStatusEntry =
        withContext(Dispatchers.IO) {
            SkillStatusEntry(engine.bridge("skill.get_status", JSONObject().put("agent_id", agentId).put("skill_name", skillName)))
        }

    public suspend fun check(agentId: String = ""): SkillStatusReport =
        withContext(Dispatchers.IO) {
            SkillStatusReport(engine.bridge("skill.check", JSONObject().put("agent_id", agentId)))
        }

    public suspend fun commands(agentId: String = ""): SkillCommandReport =
        withContext(Dispatchers.IO) {
            SkillCommandReport(engine.bridge("skill.commands", JSONObject().put("agent_id", agentId)))
        }

    public suspend fun resolveCommand(text: String, agentId: String = ""): SkillCommandResolution =
        withContext(Dispatchers.IO) {
            SkillCommandResolution(engine.bridge("skill.resolve_command", JSONObject().put("agent_id", agentId).put("text", text)))
        }

    public suspend fun runCommand(
        commandName: String,
        agentId: String = "",
        args: String? = null,
        session: SessionKey? = null,
    ): SkillCommandRun =
        withContext(Dispatchers.IO) {
            SkillCommandRun(
                engine.bridge(
                    "skill.run_command",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("command_name", commandName)
                        .put("args", args)
                        .put("session_key_json", session?.toJson()),
                ),
            )
        }

    public suspend fun setEnabled(skillName: String, agentId: String = "", enabled: Boolean): String =
        withContext(Dispatchers.IO) {
            engine.bridge(
                "skill.set_enabled",
                JSONObject().put("agent_id", agentId).put("skill_name", skillName).put("enabled", enabled),
            )
        }

    public suspend fun updateConfig(skillKey: String, patchJson: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge(
                "skill.update_config",
                JSONObject().put("agent_id", agentId).put("skill_key", skillKey).put("patch_json", patchJson),
            )
        }

    public suspend fun remediationActions(skillName: String, agentId: String = ""): List<SkillRemediationAction> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "skill.remediation_actions",
                    JSONObject().put("agent_id", agentId).put("skill_name", skillName),
                ),
                "actions",
            ).map(SkillRemediationAction::fromJsonObject)
        }

    public suspend fun snapshots(agentId: String = "", limit: Int = 50, offset: Int = 0): SkillSnapshotList =
        withContext(Dispatchers.IO) {
            SkillSnapshotList(
                engine.bridge(
                    "skill.snapshots",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("limit", limit)
                        .put("offset", offset),
                ),
            )
        }

    public suspend fun snapshot(snapshotId: String): SkillSnapshot? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("skill.get_snapshot", JSONObject().put("snapshot_id", snapshotId))
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else SkillSnapshot(raw)
        }

    public suspend fun secretRequirements(
        agentId: String = "",
        skillName: String? = null,
    ): SkillSecretRequirementReport =
        withContext(Dispatchers.IO) {
            SkillSecretRequirementReport(
                engine.bridge(
                    "skill.secret_requirements",
                    JSONObject().put("agent_id", agentId).put("skill_name", skillName),
                ),
            )
        }

    public suspend fun recordSecretAvailability(
        skillName: String,
        key: String,
        agentId: String = "",
        available: Boolean,
        source: String = "host",
    ): SkillStatusReport =
        withContext(Dispatchers.IO) {
            SkillStatusReport(
                engine.bridge(
                    "skill.record_secret_availability",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("skill_name", skillName)
                        .put("key", key)
                        .put("available", available)
                        .put("source", source),
                ),
            )
        }

    public suspend fun requestRemediation(
        skillName: String,
        actionId: String,
        agentId: String = "",
    ): SkillRemediationRun =
        withContext(Dispatchers.IO) {
            SkillRemediationRun(
                engine.bridge(
                    "skill.request_remediation",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("skill_name", skillName)
                        .put("action_id", actionId),
                ),
            )
        }

    public suspend fun updateRemediationRun(
        runId: String,
        status: String,
        agentId: String = "",
        resultJson: String? = null,
    ): SkillRemediationRun =
        withContext(Dispatchers.IO) {
            SkillRemediationRun(
                engine.bridge(
                    "skill.update_remediation_run",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("run_id", runId)
                        .put("status", status)
                        .put("result_json", resultJson),
                ),
            )
        }

    public suspend fun remediationRuns(
        agentId: String = "",
        skillName: String? = null,
        limit: Int = 50,
        offset: Int = 0,
    ): SkillRemediationRunList =
        withContext(Dispatchers.IO) {
            SkillRemediationRunList(
                engine.bridge(
                    "skill.remediation_runs",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("skill_name", skillName)
                        .put("limit", limit)
                        .put("offset", offset),
                ),
            )
        }

    public suspend fun recordRequirementResolution(
        skillName: String,
        actionId: String,
        resultJson: String,
        agentId: String = "",
    ): String =
        withContext(Dispatchers.IO) {
            engine.bridge(
                "skill.record_requirement_resolution",
                JSONObject()
                    .put("agent_id", agentId)
                    .put("skill_name", skillName)
                    .put("action_id", actionId)
                    .put("result_json", resultJson),
            )
        }

    public suspend fun install(skillContent: String, agentId: String = ""): SkillInstallResult =
        withContext(Dispatchers.IO) {
            SkillInstallResult(engine.bridge("skill.install", JSONObject().put("agent_id", agentId).put("skill_content", skillContent)))
        }

    public suspend fun install(skill: SkillInstallInput, agentId: String = ""): SkillInstallResult =
        install(skill.toInstallPayloadJson(), agentId)

    public suspend fun remove(skillName: String, agentId: String = ""): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("skill.remove", JSONObject().put("agent_id", agentId).put("skill_name", skillName))
        }

    public suspend fun reload(agentId: String = ""): List<String> =
        withContext(Dispatchers.IO) {
            JSONArray(engine.bridge("skill.reload", JSONObject().put("agent_id", agentId))).toStringList()
        }

    public suspend fun usage(agentId: String = ""): List<SkillUsageRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("skill.usage", JSONObject().put("agent_id", agentId)), "usage").map {
                SkillUsageRecord(it.toString())
            }
        }

    public suspend fun pin(skillName: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge("skill.pin", JSONObject().put("agent_id", agentId).put("skill_name", skillName))
        }

    public suspend fun unpin(skillName: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge("skill.unpin", JSONObject().put("agent_id", agentId).put("skill_name", skillName))
        }

    public suspend fun archive(skillName: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge("skill.archive", JSONObject().put("agent_id", agentId).put("skill_name", skillName))
        }

    public suspend fun restore(skillName: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge("skill.restore", JSONObject().put("agent_id", agentId).put("skill_name", skillName))
        }

    public suspend fun runCurator(agentId: String = "", dryRun: Boolean = true): CuratorRunSummary =
        withContext(Dispatchers.IO) {
            CuratorRunSummary(engine.bridge("skill.curator", JSONObject().put("agent_id", agentId).put("dry_run", dryRun)))
        }

    public suspend fun runConsolidationReview(
        agentId: String = "",
        config: LlmConfig? = null,
        dryRun: Boolean = true,
    ): SkillConsolidationReviewResult =
        withContext(Dispatchers.IO) {
            SkillConsolidationReviewResult(
                engine.bridge(
                    "evolution.consolidation_review",
                    JSONObject()
                        .put("agent_id", agentId)
                        .put("config_json", (config ?: engine.config).toJson())
                        .put("dry_run", dryRun),
                ),
            )
        }

    public suspend fun readSupportFile(skillName: String, filePath: String, agentId: String = ""): SkillSupportFileReadResult =
        withContext(Dispatchers.IO) {
            SkillSupportFileReadResult(
                engine.bridge(
                    "skill.read_support_file",
                    JSONObject().put("agent_id", agentId).put("skill_name", skillName).put("file_path", filePath),
                ),
            )
        }

    public suspend fun searchCatalog(query: String): String =
        withContext(Dispatchers.IO) { engine.bridge("skill.search_catalog", JSONObject().put("query", query), handle = 0L) }

    public suspend fun listCatalogPackages(limit: Int = 24, cursor: String? = null): CatalogPackagePage =
        withContext(Dispatchers.IO) {
            val safeLimit = limit.coerceIn(1, 100)
            val params = linkedMapOf("limit" to safeLimit.toString())
            if (!cursor.isNullOrBlank()) params["cursor"] = cursor.trim()
            CatalogPackagePage(getClawHubJson("/api/v1/packages", params))
        }

    public suspend fun getCatalogSkill(slug: String): String =
        withContext(Dispatchers.IO) { engine.bridge("skill.get_catalog_skill", JSONObject().put("slug", slug), handle = 0L) }

    public suspend fun installFromCatalog(slug: String, agentId: String = ""): String =
        withContext(Dispatchers.IO) {
            engine.bridge("skill.install_from_catalog", JSONObject().put("agent_id", agentId).put("slug", slug))
        }
}

public class EvolutionApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun listPending(): List<NapaxiJsonModel> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("evolution.pending"), "pending").map { NapaxiJsonModel(it.toString()) }
        }

    public suspend fun applyPending(pendingId: String): String =
        withContext(Dispatchers.IO) { engine.bridge("evolution.apply", JSONObject().put("pending_id", pendingId)) }

    public suspend fun rejectPending(pendingId: String): String =
        withContext(Dispatchers.IO) { engine.bridge("evolution.reject", JSONObject().put("pending_id", pendingId)) }

    public suspend fun runs(runIdsJson: String = "[]"): List<EvolutionRun> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("evolution.runs", JSONObject().put("run_ids_json", runIdsJson)), "runs").map {
                EvolutionRun(it.toString())
            }
        }

    public suspend fun diagnostics(): List<EvolutionDiagnostic> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("evolution.diagnostics"), "diagnostics").map {
                EvolutionDiagnostic(it.toString())
            }
        }
}

public class GroupApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun create(name: String, memberAgentIds: List<String>): String =
        withContext(Dispatchers.IO) {
            engine.bridge("group.create", JSONObject().put("name", name).put("members_json", JSONArray(memberAgentIds).toString()))
        }

    public suspend fun delete(groupId: String): Boolean =
        withContext(Dispatchers.IO) { engine.bridgeBool("group.delete", JSONObject().put("group_id", groupId)) }

    public suspend fun list(): List<GroupInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("group.list"), "groups").map { GroupInfo(it.toString()) }
        }

    public suspend fun get(groupId: String): GroupInfo? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("group.get", JSONObject().put("group_id", groupId))
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else GroupInfo(raw)
        }

    public suspend fun rename(groupId: String, newName: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("group.rename", JSONObject().put("group_id", groupId).put("new_name", newName))
        }

    public suspend fun updateMembers(groupId: String, memberAgentIds: List<String>): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("group.update_members", JSONObject().put("group_id", groupId).put("members_json", JSONArray(memberAgentIds).toString()))
        }

    public suspend fun setCustomPrompt(groupId: String, prompt: String?): Boolean =
        withContext(Dispatchers.IO) {
            val args = JSONObject().put("group_id", groupId)
            if (prompt != null) args.put("prompt", prompt)
            engine.bridgeBool("group.set_prompt", args)
        }

    public suspend fun messages(groupId: String): List<GroupMessage> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("group.messages", JSONObject().put("group_id", groupId)), "messages").map {
                GroupMessage(it.toString())
            }
        }

    public suspend fun clearHistory(groupId: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("group.clear", JSONObject().put("group_id", groupId))
        }

    public fun send(groupId: String, message: String, maxIterations: Int = 0): Flow<ChatEvent> =
        engine.sendToGroup(groupId, message, maxIterations)

    public fun sendToAgent(
        groupId: String,
        agentId: String,
        session: SessionKey,
        message: String,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = engine.sendToGroupAgent(groupId, agentId, session, message, maxIterations)

    public suspend fun exportState(): String =
        withContext(Dispatchers.IO) { engine.bridge("group.export") }

    public suspend fun importState(stateJson: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("group.import", JSONObject().put("state_json", stateJson))
        }
}

public class McpApi internal constructor(private val engine: NapaxiEngine, private val userId: String) {
    public suspend fun addServer(
        name: String,
        url: String,
        headersJson: String = "{}",
        transport: String? = null,
    ): McpServerActionResult =
        withContext(Dispatchers.IO) {
            val headers = JSONObject(headersJson)
            if (!transport.isNullOrBlank()) headers.put("__napaxi_transport", transport)
            McpServerActionResult(
                engine.bridge(
                    "mcp.add_server",
                    JSONObject()
                        .put("name", name)
                        .put("url", url)
                        .put("headers_json", headers.toString())
                        .put("user_id", userId),
                ),
            )
        }

    public suspend fun addServer(
        name: String,
        url: String,
        headers: Map<String, String>,
        transport: String? = null,
    ): McpServerActionResult =
        addServer(name, url, JSONObject(headers).toString(), transport)

    public suspend fun removeServer(name: String): Boolean =
        withContext(Dispatchers.IO) {
            bridgeSuccess(engine.bridge("mcp.remove_server", JSONObject().put("name", name).put("user_id", userId)))
        }

    public suspend fun listServers(): List<McpServerInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("mcp.list_servers", JSONObject().put("user_id", userId)), "servers").map {
                McpServerInfo(it.toString())
            }
        }

    public suspend fun activateServer(name: String): McpServerActionResult =
        activate(name)

    public suspend fun activate(name: String): McpServerActionResult =
        withContext(Dispatchers.IO) {
            McpServerActionResult(engine.bridge("mcp.activate_server", JSONObject().put("name", name).put("user_id", userId)))
        }

    public suspend fun startOAuth(
        name: String,
        redirectUri: String = "napaxi://oauth/mcp",
        oauthJson: String = "{}",
        clientId: String? = null,
        clientSecret: String? = null,
        authorizationUrl: String? = null,
        tokenUrl: String? = null,
        scopes: List<String> = emptyList(),
        usePkce: Boolean? = null,
        extraParams: Map<String, String> = emptyMap(),
        resource: String? = null,
    ): McpOAuthStartResult =
        withContext(Dispatchers.IO) {
            val typedOAuth = JSONObject(oauthJson.ifBlank { "{}" }).apply {
                clientId?.takeIf { it.isNotBlank() }?.let { put("client_id", it) }
                clientSecret?.takeIf { it.isNotBlank() }?.let { put("client_secret", it) }
                authorizationUrl?.takeIf { it.isNotBlank() }?.let { put("authorization_url", it) }
                tokenUrl?.takeIf { it.isNotBlank() }?.let { put("token_url", it) }
                if (scopes.isNotEmpty()) put("scopes", JSONArray(scopes))
                usePkce?.let { put("use_pkce", it) }
                if (extraParams.isNotEmpty()) put("extra_params", JSONObject(extraParams))
                resource?.takeIf { it.isNotBlank() }?.let { put("resource", it) }
            }
            McpOAuthStartResult(
                engine.bridge(
                    "mcp.start_oauth",
                    JSONObject()
                        .put("name", name)
                        .put("user_id", userId)
                        .put("redirect_uri", redirectUri)
                        .put("oauth_json", typedOAuth.toString()),
                ),
            )
        }

    public suspend fun finishOAuth(name: String, code: String, state: String): McpServerActionResult =
        withContext(Dispatchers.IO) {
            McpServerActionResult(
                engine.bridge(
                    "mcp.finish_oauth",
                    JSONObject()
                        .put("name", name)
                        .put("user_id", userId)
                        .put("code", code)
                        .put("state", state),
                ),
            )
        }

    public suspend fun deactivateServer(name: String): Boolean = deactivate(name)

    public suspend fun deactivate(name: String): Boolean =
        withContext(Dispatchers.IO) {
            bridgeSuccess(engine.bridge("mcp.deactivate_server", JSONObject().put("name", name).put("user_id", userId)))
        }

    public suspend fun listTools(serverName: String? = null): List<McpToolInfo> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "mcp.list_tools",
                    JSONObject().put("server_name", serverName ?: "").put("user_id", userId),
                ),
                "tools",
            ).map {
                McpToolInfo(it.toString())
            }
        }
}

public class AutomationApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun createJob(jobJson: String): AutomationJob =
        withContext(Dispatchers.IO) { AutomationJob(engine.bridge("automation.create", JSONObject().put("job_json", jobJson))) }

    public suspend fun createJob(job: AutomationJob): AutomationJob = createJob(job.toJson())

    public suspend fun createAutomationJob(jobJson: String): AutomationJob = createJob(jobJson)

    public suspend fun createAutomationJob(job: AutomationJob): AutomationJob = createJob(job)

    public suspend fun updateJob(jobId: String, patchJson: String): AutomationJob =
        withContext(Dispatchers.IO) {
            AutomationJob(engine.bridge("automation.update", JSONObject().put("job_id", jobId).put("patch_json", patchJson)))
        }

    public suspend fun updateJob(jobId: String, patch: JSONObject): AutomationJob =
        updateJob(jobId, patch.toString())

    public suspend fun updateJob(jobId: String, patch: Map<String, Any?>): AutomationJob =
        updateJob(jobId, JSONObject(patch))

    public suspend fun updateAutomationJob(jobId: String, patchJson: String): AutomationJob =
        updateJob(jobId, patchJson)

    public suspend fun updateAutomationJob(jobId: String, patch: JSONObject): AutomationJob =
        updateJob(jobId, patch)

    public suspend fun updateAutomationJob(jobId: String, patch: Map<String, Any?>): AutomationJob =
        updateJob(jobId, patch)

    public suspend fun deleteJob(jobId: String): Boolean =
        withContext(Dispatchers.IO) { engine.bridgeBool("automation.delete", JSONObject().put("job_id", jobId)) }

    public suspend fun deleteAutomationJob(jobId: String): Boolean = deleteJob(jobId)

    public suspend fun listJobs(filterJson: String = "{}"): List<AutomationJob> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("automation.list", JSONObject().put("filter_json", filterJson)), "jobs").map {
                AutomationJob(it.toString())
            }
        }

    public suspend fun listAutomationJobs(
        accountId: String? = null,
        agentId: String? = null,
        enabled: Boolean? = null,
    ): List<AutomationJob> = listJobs(
        JSONObject()
            .apply {
                accountId?.let { put("accountId", it) }
                agentId?.let { put("agentId", it) }
                enabled?.let { put("enabled", it) }
            }
            .toString(),
    )

    public suspend fun getJob(jobId: String): AutomationJob =
        withContext(Dispatchers.IO) {
            AutomationJob(engine.bridge("automation.get", JSONObject().put("job_id", jobId)))
        }

    public suspend fun getAutomationJob(jobId: String): AutomationJob? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("automation.get", JSONObject().put("job_id", jobId))
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else AutomationJob(raw)
        }

    public suspend fun runJob(jobId: String, mode: String = "manual"): AutomationRun =
        withContext(Dispatchers.IO) {
            AutomationRun(engine.bridge("automation.run", JSONObject().put("job_id", jobId).put("mode", mode)))
        }

    public suspend fun runAutomationJob(jobId: String, mode: String = "manual"): AutomationRun =
        runJob(jobId, mode)

    public suspend fun listRuns(jobId: String? = null, limit: Long = 50, offset: Long = 0): List<AutomationRun> =
        withContext(Dispatchers.IO) {
            val args = JSONObject().put("limit", limit).put("offset", offset)
            if (jobId != null) args.put("job_id", jobId)
            jsonArrayOfObjects(engine.bridge("automation.runs", args), "runs").map {
                AutomationRun(it.toString())
            }
        }

    public suspend fun listAutomationRuns(jobId: String? = null, limit: Long = 200, offset: Long = 0): List<AutomationRun> =
        listRuns(jobId, limit, offset)

    public suspend fun nextWake(): AutomationWake? = getNextAutomationWake()

    public suspend fun getNextAutomationWake(): AutomationWake? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("automation.next_wake")
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else AutomationWake(raw)
        }

    public suspend fun recordWake(jobId: String, source: String): AutomationRun =
        withContext(Dispatchers.IO) {
            AutomationRun(engine.bridge("automation.record_wake", JSONObject().put("job_id", jobId).put("source", source)))
        }

    public suspend fun recordAutomationWake(jobId: String, source: String): AutomationRun =
        recordWake(jobId, source)
}

public class A2AApi internal constructor(private val engine: NapaxiEngine) {
    public val localTransportEvents: List<A2ALocalTransportEvent>
        get() = emptyList()

    public fun generateLocalPairingSecret(byteLength: Int = 16): String =
        A2APairing.generateLocalPairingSecret(byteLength)

    public fun normalizePairingSecret(value: String): String =
        A2APairing.normalizePairingSecret(value)

    public fun formatPairingSecret(value: String): String =
        A2APairing.formatPairingSecret(value)

    public fun pairingCodeFromIdentity(peerId: String, publicKey: String): String =
        A2APairing.pairingCodeFromIdentity(peerId, publicKey)

    public fun pairingKey(peer: A2ALocalPeerAdvertisement): String =
        A2APairing.pairingKey(peer.peerId, peer.publicKey)

    public fun deriveLocalSharedSecret(
        localPeerId: String,
        localPublicKey: String,
        localPairingSecret: String,
        peer: A2ALocalPeerAdvertisement,
        remotePairingSecret: String,
    ): String =
        A2APairing.deriveLocalSharedSecret(
            localPeerId = localPeerId,
            localPublicKey = localPublicKey,
            localPairingSecret = localPairingSecret,
            remotePeerId = peer.peerId,
            remotePublicKey = peer.publicKey,
            remotePairingSecret = remotePairingSecret,
        )

    public suspend fun agentCard(agentId: String = ""): A2AAgentCard =
        withContext(Dispatchers.IO) {
            A2AAgentCard(engine.bridge("a2a.agent_card", JSONObject().put("agent_id", agentId)))
        }

    public suspend fun createPeerInvite(agentId: String, optionsJson: String = "{}"): A2APeerInvite =
        withContext(Dispatchers.IO) {
            A2APeerInvite(
                engine.bridge(
                    "a2a.create_peer_invite",
                    JSONObject().put("agent_id", agentId).put("options_json", optionsJson),
                ),
            )
        }

    public suspend fun createPeerInvite(agentId: String, options: JSONObject): A2APeerInvite =
        createPeerInvite(agentId, options.toString())

    public suspend fun acceptPeerInvite(envelopeJson: String): A2APeer =
        withContext(Dispatchers.IO) {
            A2APeer(engine.bridge("a2a.accept_peer_invite", JSONObject().put("envelope_json", envelopeJson)))
        }

    public suspend fun acceptPeerInvite(envelope: A2ADeepLinkEnvelope): A2APeer =
        acceptPeerInvite(envelope.toJsonString())

    public suspend fun listPeers(agentId: String = ""): List<A2APeer> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("a2a.list_peers", JSONObject().put("agent_id", agentId)), "peers").map {
                A2APeer(it.toString())
            }
        }

    public suspend fun deletePeer(peerId: String): Boolean =
        withContext(Dispatchers.IO) { engine.bridgeBool("a2a.delete_peer", JSONObject().put("peer_id", peerId)) }

    public suspend fun openPeerSession(
        peer: A2APeer,
        transport: String = "lan_websocket",
        endpoint: String = "",
    ): A2APeerSession =
        withContext(Dispatchers.IO) {
            A2APeerSession(
                engine.bridge(
                    "a2a.open_peer_session",
                    JSONObject()
                        .put("peer_json", peer.rawJson)
                        .put("transport", transport)
                        .put("endpoint", endpoint),
                ),
            )
        }

    public suspend fun listPeerSessions(peerId: String = ""): List<A2APeerSession> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge("a2a.list_peer_sessions", JSONObject().put("peer_id", peerId)),
                "sessions",
            ).map { A2APeerSession(it.toString()) }
        }

    public suspend fun createTaskMessage(
        sessionId: String,
        message: String,
        optionsJson: String = "{}",
    ): A2APeerMessage =
        withContext(Dispatchers.IO) {
            A2APeerMessage(
                engine.bridge(
                    "a2a.create_task_message",
                    JSONObject()
                        .put("session_id", sessionId)
                        .put("message", message)
                        .put("options_json", optionsJson),
                ),
            )
        }

    public suspend fun createTaskProgressMessage(
        sessionId: String,
        taskId: String,
        message: String,
        progressJson: String = "{}",
    ): A2APeerMessage =
        withContext(Dispatchers.IO) {
            A2APeerMessage(
                engine.bridge(
                    "a2a.create_task_progress_message",
                    JSONObject()
                        .put("session_id", sessionId)
                        .put("task_id", taskId)
                        .put("message", message)
                        .put("progress_json", progressJson),
                ),
            )
        }

    public suspend fun createTaskResultMessage(
        sessionId: String,
        taskId: String,
        resultJson: String = "{}",
    ): A2APeerMessage =
        withContext(Dispatchers.IO) {
            A2APeerMessage(
                engine.bridge(
                    "a2a.create_task_result_message",
                    JSONObject()
                        .put("session_id", sessionId)
                        .put("task_id", taskId)
                        .put("result_json", resultJson),
                ),
            )
        }

    public suspend fun recordPeerMessage(message: A2APeerMessage, source: String = "local_transport"): A2ADeliveryRecord =
        recordPeerMessage(message.toJsonString(), source)

    public suspend fun recordPeerMessage(messageJson: String, source: String = "local_transport"): A2ADeliveryRecord =
        withContext(Dispatchers.IO) {
            A2ADeliveryRecord(
                engine.bridge(
                    "a2a.record_peer_message",
                    JSONObject().put("message_json", messageJson).put("source", source),
                ),
            )
        }

    public suspend fun recordDeliveryStatus(
        message: A2APeerMessage,
        status: String,
        error: String = "",
    ): A2ADeliveryRecord =
        recordDeliveryStatus(message.toJsonString(), status, error)

    public suspend fun recordDeliveryStatus(
        messageJson: String,
        status: String,
        error: String = "",
    ): A2ADeliveryRecord =
        withContext(Dispatchers.IO) {
            A2ADeliveryRecord(
                engine.bridge(
                    "a2a.record_delivery_status",
                    JSONObject()
                        .put("message_json", messageJson)
                        .put("status", status)
                        .put("error", error),
                ),
            )
        }

    public suspend fun listPeerMessages(sessionId: String, limit: Long = 100, offset: Long = 0): List<A2APeerMessage> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "a2a.list_peer_messages",
                    JSONObject().put("session_id", sessionId).put("limit", limit).put("offset", offset),
                ),
                "messages",
            ).map { A2APeerMessage(it.toString()) }
        }

    public suspend fun listDeliveryRecords(sessionId: String, limit: Long = 100, offset: Long = 0): List<A2ADeliveryRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "a2a.list_delivery_records",
                    JSONObject().put("session_id", sessionId).put("limit", limit).put("offset", offset),
                ),
                "deliveries",
            ).map { A2ADeliveryRecord(it.toString()) }
        }

    public suspend fun localTransportStatus(): A2ALocalTransportStatus =
        A2ALocalTransportStatus.fromMap(localTransportUnsupported())

    public suspend fun checkLocalTransportPermission(): Boolean =
        false

    public suspend fun requestLocalTransportPermission(): Boolean =
        false

    public suspend fun startLocalTransport(
        peerId: String = "",
        agentId: String = "",
        displayName: String = "",
        publicKey: String = "",
    ): A2ALocalTransportStatus =
        A2ALocalTransportStatus.fromMap(localTransportUnsupported())

    public suspend fun stopLocalTransport(): A2ALocalTransportStatus =
        A2ALocalTransportStatus.fromMap(localTransportUnsupported())

    public suspend fun discoverLocalPeers(timeoutMs: Long = 5000): List<A2ALocalPeerAdvertisement> =
        emptyList()

    public suspend fun sendPeerMessage(message: A2APeerMessage, endpoint: String): Boolean =
        throw UnsupportedOperationException("A2A local transport is implemented by the Flutter platform plugin on Android.")

    private fun localTransportUnsupported(): Map<String, Any> = mapOf(
        "supported" to false,
        "running" to false,
        "transport" to "lan_tcp_jsonl",
        "serviceType" to "_napaxi-a2a._tcp.",
        "reason" to "native_android_transport_not_bound",
    )

    public suspend fun acceptDeepLink(envelopeJson: String, source: String = "deep_link"): A2ATaskRecord =
        withContext(Dispatchers.IO) {
            A2ATaskRecord(
                engine.bridge(
                    "a2a.accept_deep_link",
                    JSONObject().put("envelope_json", envelopeJson).put("source", source),
                ),
            )
        }

    public suspend fun acceptDeepLink(envelope: A2ADeepLinkEnvelope, source: String = "deep_link"): A2ATaskRecord =
        acceptDeepLink(envelope.toJsonString(), source)

    public suspend fun runTask(taskId: String, mode: String = "confirm"): A2ATaskRecord =
        withContext(Dispatchers.IO) {
            A2ATaskRecord(engine.bridge("a2a.run_task", JSONObject().put("task_id", taskId).put("mode", mode)))
        }

    public suspend fun listTasks(filterJson: String = "{}", limit: Long = 100, offset: Long = 0): List<A2ATaskRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(
                engine.bridge(
                    "a2a.list_tasks",
                    JSONObject().put("filter_json", filterJson).put("limit", limit).put("offset", offset),
                ),
                "tasks",
            ).map { A2ATaskRecord(it.toString()) }
        }

    public suspend fun getTask(taskId: String): A2ATaskRecord? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("a2a.get_task", JSONObject().put("task_id", taskId))
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else A2ATaskRecord(raw)
        }

    public suspend fun buildResultLink(taskId: String, callbackUrl: String): A2AResultLink =
        withContext(Dispatchers.IO) {
            A2AResultLink(
                engine.bridge(
                    "a2a.build_result_link",
                    JSONObject().put("task_id", taskId).put("callback_url", callbackUrl),
                ),
            )
        }

    public suspend fun recordResultEnvelope(envelopeJson: String): RawJsonModel =
        withContext(Dispatchers.IO) {
            RawJsonModel(engine.bridge("a2a.record_result", JSONObject().put("envelope_json", envelopeJson)))
        }

    public suspend fun recordResultEnvelope(envelope: A2ADeepLinkEnvelope): RawJsonModel =
        recordResultEnvelope(envelope.toJsonString())
}

public class AgentAppApi internal constructor(private val engine: NapaxiEngine) {
    public suspend fun registerPackage(packageJson: String): AgentAppPackage =
        withContext(Dispatchers.IO) {
            AgentAppPackage(engine.bridge("agent_app.register", JSONObject().put("package_json", packageJson)))
        }

    public suspend fun registerPackage(packageDef: AgentAppPackage): AgentAppPackage =
        registerPackage(packageDef.toJsonString())

    public suspend fun listPackages(): List<AgentAppPackage> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("agent_app.list"), "packages").map { AgentAppPackage(it.toString()) }
        }

    public suspend fun getPackage(agentId: String): AgentAppPackage? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("agent_app.get", JSONObject().put("agent_id", agentId))
            if (raw.isBlank() || raw == "null") null else AgentAppPackage(raw)
        }

    public suspend fun deletePackage(agentId: String): Boolean =
        withContext(Dispatchers.IO) { engine.bridgeBool("agent_app.delete", JSONObject().put("agent_id", agentId)) }

    public suspend fun submitActionResult(resultJson: String): AgentAppActionRecord =
        withContext(Dispatchers.IO) {
            AgentAppActionRecord(engine.bridge("agent_app.submit_result", JSONObject().put("result_json", resultJson)))
        }

    public suspend fun submitActionResult(result: AgentAppActionResult): AgentAppActionRecord =
        submitActionResult(result.toJsonString())

    public suspend fun submitResult(resultJson: String): AgentAppActionRecord =
        withContext(Dispatchers.IO) {
            AgentAppActionRecord(engine.bridge("agent_app.submit_result", JSONObject().put("result_json", resultJson)))
        }

    public suspend fun submitResult(result: AgentAppActionResult): AgentAppActionRecord =
        submitResult(result.toJsonString())

    public suspend fun listActionProposals(agentId: String): List<AgentAppActionProposal> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("agent_app.list_proposals", JSONObject().put("agent_id", agentId)), "proposals").map {
                AgentAppActionProposal(it.toString())
            }
        }

    public suspend fun listProposals(agentId: String = ""): List<AgentAppActionRecord> =
        withContext(Dispatchers.IO) {
            jsonArrayOfObjects(engine.bridge("agent_app.list_proposals", JSONObject().put("agent_id", agentId)), "proposals").map {
                AgentAppActionRecord(it.toString())
            }
        }

    public suspend fun getActionProposal(requestId: String): AgentAppActionProposal? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("agent_app.get_proposal", JSONObject().put("request_id", requestId))
            if (raw.isBlank() || raw == "null") null else AgentAppActionProposal(raw)
        }

    public suspend fun getProposal(requestId: String): AgentAppActionRecord? =
        withContext(Dispatchers.IO) {
            val raw = engine.bridge("agent_app.get_proposal", JSONObject().put("request_id", requestId))
            if (raw.isBlank() || raw == "null" || raw.contains(""""error"""")) null else AgentAppActionRecord(raw)
        }

    public suspend fun acceptTrigger(triggerJson: String): AcceptedAgentTrigger =
        withContext(Dispatchers.IO) {
            AcceptedAgentTrigger(engine.bridge("agent_app.accept_trigger", JSONObject().put("trigger_json", triggerJson)))
        }

    public suspend fun acceptTrigger(request: AgentTriggerRequest): AcceptedAgentTrigger =
        acceptTrigger(request.toJson())
}

public class FileBridgeApi internal constructor(
    private val engine: NapaxiEngine,
    private val context: Context,
) {
    public suspend fun init(accountId: String? = null, agentId: String? = null): Boolean =
        withContext(Dispatchers.IO) {
            if (accountId != null || agentId != null) {
                engine.bridgeBool(
                    "file_bridge.init_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID),
                )
            } else {
                engine.bridgeBool("file_bridge.init")
            }
        }

    public suspend fun saveMessageAttachments(
        threadId: String,
        userMessageIndex: Int,
        attachments: List<McAttachment>,
    ): Boolean = withContext(Dispatchers.IO) {
        engine.bridgeBool(
            "file_bridge.save_attachments",
            JSONObject()
                .put("thread_id", threadId)
                .put("user_msg_index", userMessageIndex)
                .put("attachments_json", attachments.toJsonArrayString()),
        )
    }

    public suspend fun loadThreadAttachments(threadId: String): String =
        withContext(Dispatchers.IO) {
            engine.bridge("file_bridge.load_attachments", JSONObject().put("thread_id", threadId))
        }

    public suspend fun deleteThreadAttachments(threadId: String): Boolean =
        withContext(Dispatchers.IO) {
            engine.bridgeBool("file_bridge.delete_attachments", JSONObject().put("thread_id", threadId))
        }

    public suspend fun sandboxToReal(sandboxPath: String, accountId: String? = null, agentId: String? = null): String? =
        withContext(Dispatchers.IO) {
            val raw = if (accountId != null || agentId != null) {
                engine.bridge(
                    "file_bridge.sandbox_to_real_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID)
                        .put("sandbox_path", sandboxPath),
                )
            } else {
                engine.bridge("file_bridge.sandbox_to_real", JSONObject().put("sandbox_path", sandboxPath))
            }
            raw.takeIf { it.isNotBlank() && it != "null" }
        }

    public suspend fun realToSandbox(realPath: String, accountId: String? = null, agentId: String? = null): String? =
        withContext(Dispatchers.IO) {
            val raw = if (accountId != null || agentId != null) {
                engine.bridge(
                    "file_bridge.real_to_sandbox_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID)
                        .put("real_path", realPath),
                )
            } else {
                engine.bridge("file_bridge.real_to_sandbox", JSONObject().put("real_path", realPath))
            }
            raw.takeIf { it.isNotBlank() && it != "null" }
        }

    public suspend fun detectFileReferences(text: String): List<ResolvedFile> =
        detectFileReferencesJson(text).parseJsonArrayOrObjectList("files").map {
            ResolvedFile.fromJsonObject(it)
        }

    public suspend fun detectFileReferencesScoped(
        text: String,
        accountId: String,
        agentId: String,
    ): List<ResolvedFile> =
        detectFileReferencesJson(text, accountId, agentId).parseJsonArrayOrObjectList("files").map {
            ResolvedFile.fromJsonObject(it)
        }

    public suspend fun detectFileReferencesJson(text: String, accountId: String? = null, agentId: String? = null): String =
        withContext(Dispatchers.IO) {
            if (accountId != null || agentId != null) {
                engine.bridge(
                    "file_bridge.detect_refs_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID)
                        .put("text", text),
                )
            } else {
                engine.bridge("file_bridge.detect_refs", JSONObject().put("text", text))
            }
        }

    public suspend fun resolveFile(sandboxPath: String): File? =
        sandboxToReal(sandboxPath)?.let(::File)?.takeIf { it.exists() && it.isFile }

    public suspend fun resolveFileScoped(
        sandboxPath: String,
        accountId: String,
        agentId: String,
    ): File? =
        sandboxToReal(sandboxPath, accountId, agentId)?.let(::File)?.takeIf { it.exists() && it.isFile }

    public suspend fun deleteFile(sandboxPath: String): Boolean =
        deleteSandboxFile(sandboxPath)

    public suspend fun deleteFileScoped(
        sandboxPath: String,
        accountId: String,
        agentId: String,
    ): Boolean =
        deleteSandboxFile(sandboxPath, accountId, agentId)

    public suspend fun deleteSandboxFile(sandboxPath: String, accountId: String? = null, agentId: String? = null): Boolean =
        withContext(Dispatchers.IO) {
            if (accountId != null || agentId != null) {
                engine.bridgeBool(
                    "file_bridge.delete_sandbox_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID)
                        .put("sandbox_path", sandboxPath),
                )
            } else {
                engine.bridgeBool("file_bridge.delete_sandbox", JSONObject().put("sandbox_path", sandboxPath))
            }
        }

    public suspend fun listFiles(subdir: String? = null, recursive: Boolean = false): List<WorkspaceFileInfo> =
        listWorkspaceFilesystemJson(subdir, recursive).parseJsonArrayOrObjectList("files").map {
            WorkspaceFileInfo.fromJsonObject(it)
        }

    public suspend fun listFilesScoped(
        accountId: String,
        agentId: String,
        subdir: String? = null,
        recursive: Boolean = false,
    ): List<WorkspaceFileInfo> =
        listWorkspaceFilesystemJson(subdir, recursive, accountId, agentId).parseJsonArrayOrObjectList("files").map {
            WorkspaceFileInfo.fromJsonObject(it)
        }

    public suspend fun listWorkspaceFilesystem(subdir: String? = null, recursive: Boolean = false, accountId: String? = null, agentId: String? = null): String =
        listWorkspaceFilesystemJson(subdir, recursive, accountId, agentId)

    public suspend fun listWorkspaceFilesystemJson(subdir: String? = null, recursive: Boolean = false, accountId: String? = null, agentId: String? = null): String =
        withContext(Dispatchers.IO) {
            val args = JSONObject().put("recursive", recursive)
            if (subdir != null) args.put("subdir", subdir)
            if (accountId != null || agentId != null) {
                args.put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                    .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID)
                engine.bridge("file_bridge.list_fs_scoped", args)
            } else {
                engine.bridge("file_bridge.list_fs", args)
            }
        }

    public suspend fun workspaceSizeScoped(accountId: String, agentId: String): Long =
        workspaceSize(accountId, agentId)

    public suspend fun workspaceSize(accountId: String? = null, agentId: String? = null): Long =
        withContext(Dispatchers.IO) {
            if (accountId != null || agentId != null) {
                engine.bridgeLong(
                    "file_bridge.workspace_size_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID),
                )
            } else {
                engine.bridgeLong("file_bridge.workspace_size")
            }
        }

    public suspend fun workspaceDirScoped(accountId: String, agentId: String): String =
        workspaceDir(accountId, agentId)

    public suspend fun workspaceDir(accountId: String? = null, agentId: String? = null): String =
        withContext(Dispatchers.IO) {
            if (accountId != null || agentId != null) {
                engine.bridge(
                    "file_bridge.workspace_dir_scoped",
                    JSONObject()
                        .put("account_id", accountId ?: NapaxiEngine.DEFAULT_ACCOUNT_ID)
                        .put("agent_id", agentId ?: NapaxiEngine.DEFAULT_AGENT_ID),
                )
            } else {
                engine.bridge("file_bridge.workspace_dir")
            }
        }

    public suspend fun rootfsDir(): String =
        withContext(Dispatchers.IO) { engine.bridge("file_bridge.rootfs_dir") }

    public suspend fun skillsDir(): String =
        withContext(Dispatchers.IO) { engine.bridge("file_bridge.skills_dir") }

    public suspend fun openLocalFile(
        path: String,
        mimeType: String = "application/octet-stream",
    ): String = withContext(Dispatchers.IO) {
        openLocalFileJson(context, path, mimeType)
    }

    public suspend fun openLocalFileResult(
        path: String,
        mimeType: String = "application/octet-stream",
    ): JSONObject = JSONObject(openLocalFile(path, mimeType))

    public companion object {
        @JvmStatic
        public fun openLocalFileJson(
            context: Context,
            path: String,
            mimeType: String = "application/octet-stream",
        ): String {
            if (path.isBlank()) {
                return JSONObject().put("success", false).put("error", "path is required").toString()
            }
            val file = File(path)
            if (!file.exists() || !file.isFile) {
                return JSONObject()
                    .put("success", false)
                    .put("error", "File does not exist: $path")
                    .toString()
            }
            return runCatching {
                val uri = NapaxiFileProvider.uriForFile(context, file)
                val resolvedMimeType = mimeType.ifBlank { "application/octet-stream" }
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, resolvedMimeType)
                    clipData = ClipData.newUri(context.contentResolver, file.name, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(Intent.createChooser(intent, "Open file").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
                JSONObject()
                    .put("success", true)
                    .put("path", path)
                    .put("mimeType", resolvedMimeType)
                    .toString()
            }.getOrElse { error ->
                JSONObject()
                    .put("success", false)
                    .put("error", error.message ?: "Failed to open file")
                    .toString()
            }
        }
    }
}

public object NapaxiFileBridge {
    public val isSupported: Boolean
        get() = true

    @JvmStatic
    public fun instance(engine: NapaxiEngine): FileBridgeApi = engine.fileBridge

    @JvmStatic
    public suspend fun init(
        engine: NapaxiEngine,
        accountId: String? = null,
        agentId: String? = null,
    ): Boolean = engine.initFileBridge(accountId, agentId)

    @JvmStatic
    public fun openLocalFileJson(
        context: Context,
        path: String,
        mimeType: String = "application/octet-stream",
    ): String = FileBridgeApi.openLocalFileJson(context, path, mimeType)

    @JvmStatic
    public fun openLocalFileResult(
        context: Context,
        path: String,
        mimeType: String = "application/octet-stream",
    ): JSONObject = JSONObject(openLocalFileJson(context, path, mimeType))
}

public class ApkInstallerApi internal constructor(
    private val engine: NapaxiEngine,
    private val context: Context,
) {
    public suspend fun install(path: String): String =
        withContext(Dispatchers.IO) {
            AndroidPlatformToolExecutor(context).execute("install_apk", JSONObject().put("path", path).toString())
        }

    public suspend fun installResult(path: String): NapaxiApkInstallResult =
        NapaxiApkInstallResult.fromJson(install(path))
}

public object NapaxiApkInstaller {
    public val isSupported: Boolean
        get() = AndroidPlatformToolExecutor.isSupported

    @JvmStatic
    public fun installApk(context: Context, apkPath: String): NapaxiApkInstallResult =
        NapaxiApkInstallResult.fromJson(installApkJson(context, apkPath))

    @JvmStatic
    public fun installApkJson(context: Context, apkPath: String): String =
        if (!isSupported) {
            JSONObject()
                .put("success", false)
                .put("error", "APK installation is only supported on Android.")
                .toString()
        } else {
            AndroidPlatformToolExecutor(context.applicationContext)
                .execute("install_apk", JSONObject().put("path", apkPath).toString())
        }
}

private fun JSONObject.scope(accountId: String, agentId: String): JSONObject =
    put("account_id", accountId).put("agent_id", agentId)

private fun jsonArrayOfObjects(rawJson: String, key: String): List<JSONObject> =
    rawJson.parseJsonArrayOrObjectList(key)

private fun bridgeSuccess(rawJson: String): Boolean {
    val obj = runCatching { JSONObject(rawJson) }.getOrNull() ?: return false
    return obj.optBoolean("success", false) || obj.optBoolean("ok", false)
}

private fun getClawHubJson(path: String, queryParams: Map<String, String>): String {
    val base = "https://wry-manatee-359.convex.site"
    val query = queryParams.entries.joinToString("&") { (key, value) ->
        "${key.urlEncode()}=${value.urlEncode()}"
    }
    val connection = (URL("$base$path?$query").openConnection() as HttpURLConnection).apply {
        connectTimeout = 15_000
        readTimeout = 15_000
        requestMethod = "GET"
        setRequestProperty("User-Agent", "napaxi-sdk/1.0")
    }
    return try {
        val code = connection.responseCode
        val stream = if (code in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
        if (code in 200..299) {
            body
        } else {
            JSONObject().put("items", JSONArray()).put("error", "HTTP $code: $body").toString()
        }
    } catch (error: Throwable) {
        JSONObject().put("items", JSONArray()).put("error", error.toString()).toString()
    } finally {
        connection.disconnect()
    }
}

private fun String.urlEncode(): String = URLEncoder.encode(this, "UTF-8")

private fun List<McAttachment>.toJsonArrayString(sandboxPaths: List<String>? = null): String {
    val arr = JSONArray()
    forEachIndexed { index, attachment -> arr.put(attachment.toJsonObject(sandboxPaths?.getOrNull(index))) }
    return arr.toString()
}
