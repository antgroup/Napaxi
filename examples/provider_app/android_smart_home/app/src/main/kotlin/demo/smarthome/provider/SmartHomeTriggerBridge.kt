package demo.smarthome.provider

import android.content.Context
import agent.provider.sdk.AgentProvider
import agent.provider.sdk.AgentTriggerRequest
import agent.provider.sdk.AgentTriggerSubmitResult
import agent.provider.sdk.TrustedHostBinding
import agent.provider.sdk.TrustedHostStore
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

data class SmartHomeTriggerSubmit(
    val request: AgentTriggerRequest?,
    val binding: TrustedHostBinding?,
    val status: String,
    val message: String,
)

object SmartHomeTriggerBridge {
    fun latestBinding(context: Context): TrustedHostBinding? =
        TrustedHostStore(context, SmartHomePackage.PROVIDER_ID).loadLatestBinding()

    fun buildRequest(
        message: String,
        eventType: String,
        payloadJson: String,
        source: String,
    ): AgentTriggerRequest {
        val now = Instant.now()
        val requestId = UUID.randomUUID().toString()
        return AgentTriggerRequest(
            requestId = requestId,
            providerId = SmartHomePackage.PROVIDER_ID,
            agentId = SmartHomePackage.AGENT_ID,
            message = message,
            source = source,
            eventType = eventType,
            payloadJson = payloadJson,
            createdAt = now.toString(),
            expiresAt = now.plus(5, ChronoUnit.MINUTES).toString(),
            nonce = UUID.randomUUID().toString(),
            idempotencyKey = requestId,
        )
    }

    fun submitBackground(
        context: Context,
        event: AIniceBridgeEvent,
        source: String = "mijia_ainice_notification",
    ): SmartHomeTriggerSubmit {
        val binding = latestBinding(context)
            ?: return SmartHomeTriggerSubmit(
                request = null,
                binding = null,
                status = "no_binding",
                message = "已收到米家电子围栏事件，但尚未连接 Napaxi。",
            )
        val request = buildRequest(
            message = event.message,
            eventType = event.eventType,
            payloadJson = event.payloadJson,
            source = source,
        )
        val result = AgentProvider.submitBackgroundTrigger(context, request, binding)
        val message = when (result.status) {
            AgentTriggerSubmitResult.ACCEPTED,
            AgentTriggerSubmitResult.QUEUED -> "Napaxi Agent 已收到米家电子围栏事件。"
            AgentTriggerSubmitResult.UNSUPPORTED -> "Napaxi 当前未开放后台 trigger，请在应用内手动测试推送。"
            AgentTriggerSubmitResult.HOST_UNAVAILABLE -> "Napaxi 后台服务不可用，请打开 Napaxi 后重试。"
            else -> result.error?.message ?: "Napaxi 拒绝了米家电子围栏事件。"
        }
        return SmartHomeTriggerSubmit(
            request = request,
            binding = binding,
            status = result.status,
            message = message,
        )
    }
}
