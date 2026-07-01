package com.napaxi.android

import android.content.res.AssetManager

internal object NapaxiNative {
    init {
        System.loadLibrary("napaxi_api_bridge")
    }

    @JvmStatic external fun registerAssetManager(assetManager: AssetManager)
    @JvmStatic external fun registerToolRequestCallback(callback: ToolRequestCallback?)
    @JvmStatic external fun createEngine(configJson: String, platformContextJson: String): Long
    @JvmStatic external fun updateConfig(handle: Long, configJson: String): Boolean
    @JvmStatic external fun getConfig(handle: Long): String
    @JvmStatic external fun ensureAgentReady(handle: Long, configJson: String): Boolean
    @JvmStatic external fun disposeEngine(handle: Long)
    @JvmStatic external fun getOrCreateAgent(handle: Long, agentId: String, configJson: String): String
    @JvmStatic external fun listAgents(handle: Long): String
    @JvmStatic external fun createSession(
        handle: Long,
        configJson: String,
        agentId: String,
        channelType: String,
        accountId: String,
        existingThreadId: String,
    ): String

    @JvmStatic external fun sendToSession(
        handle: Long,
        configJson: String,
        agentId: String,
        sessionKeyJson: String,
        message: String,
        attachmentsJson: String,
        maxIterations: Int,
    ): String

    @JvmStatic external fun sendToSessionStream(
        handle: Long,
        configJson: String,
        agentId: String,
        sessionKeyJson: String,
        message: String,
        attachmentsJson: String,
        maxIterations: Int,
        callback: NativeStreamCallback,
    )

    @JvmStatic external fun cancelSession(
        handle: Long,
        configJson: String,
        agentId: String,
        sessionKeyJson: String,
    ): Boolean

    @JvmStatic external fun listSessions(
        handle: Long,
        configJson: String,
        agentId: String,
        accountId: String,
    ): String

    @JvmStatic external fun getHistory(
        handle: Long,
        configJson: String,
        agentId: String,
        threadId: String,
    ): String

    @JvmStatic external fun updateCustomTools(handle: Long, toolsJson: String): Boolean
    @JvmStatic external fun resolveToolExecution(
        requestId: Long,
        result: String,
        isError: Boolean,
    ): Boolean

    @JvmStatic external fun callBridge(method: String, handle: Long, argsJson: String): String
}

internal interface ToolRequestCallback {
    fun onToolRequest(requestJson: String)
}

internal interface NativeStreamCallback {
    fun onEvent(eventJson: String)
    fun onComplete()
}
