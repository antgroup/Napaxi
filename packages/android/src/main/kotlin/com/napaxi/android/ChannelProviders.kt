package com.napaxi.android

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.json.JSONArray
import org.json.JSONObject

public data class NapaxiChannelProviderManifest(
    val providerId: String,
    val channelName: String,
    val displayName: String,
    val description: String = "",
    val accountId: String = "default",
    val surfaceKind: String = NapaxiChannelSurfaceKind.CUSTOM,
    val endpointKinds: List<String> = listOf(NapaxiChannelEndpointKind.DIRECT),
    val modalities: List<String> = listOf(NapaxiChannelModality.TEXT),
    val contentFormats: List<String> = listOf(NapaxiChannelContentFormat.PLAIN_TEXT),
    val transport: String = "host_adapter",
    val authRequirements: List<String> = emptyList(),
    val backgroundRequirements: List<String> = emptyList(),
    val config: JSONObject = JSONObject(),
) {
    public fun toRegistration(): NapaxiChannelRegistration = NapaxiChannelRegistration(
        name = channelName,
        type = channelName,
        accountId = accountId,
        surfaceKind = surfaceKind,
        endpointKind = endpointKinds.firstOrNull(),
        modalities = modalities,
        contentFormats = contentFormats,
        transport = transport,
        config = toJsonObject(),
    )

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("provider_id", providerId)
        .put("channel_name", channelName)
        .put("display_name", displayName)
        .put("account_id", accountId)
        .put("surface_kind", surfaceKind)
        .put("transport", transport)
        .apply {
            if (description.isNotBlank()) put("description", description)
            if (endpointKinds.isNotEmpty()) put("endpoint_kinds", JSONArray(endpointKinds))
            if (modalities.isNotEmpty()) put("modalities", JSONArray(modalities))
            if (contentFormats.isNotEmpty()) put("content_formats", JSONArray(contentFormats))
            if (authRequirements.isNotEmpty()) put("auth_requirements", JSONArray(authRequirements))
            if (backgroundRequirements.isNotEmpty()) put("background_requirements", JSONArray(backgroundRequirements))
            if (config.length() > 0) put("config", config)
        }

    public companion object {
        @JvmStatic
        public fun im(
            providerId: String,
            channelName: String,
            displayName: String,
            description: String = "",
            accountId: String = "default",
            endpointKinds: List<String> = listOf(NapaxiChannelEndpointKind.DIRECT),
            modalities: List<String> = listOf(NapaxiChannelModality.TEXT),
            contentFormats: List<String> = listOf(NapaxiChannelContentFormat.PLAIN_TEXT),
            transport: String = "host_adapter",
            authRequirements: List<String> = emptyList(),
            backgroundRequirements: List<String> = emptyList(),
            config: JSONObject = JSONObject(),
        ): NapaxiChannelProviderManifest = NapaxiChannelProviderManifest(
            providerId = providerId,
            channelName = channelName,
            displayName = displayName,
            description = description,
            accountId = accountId,
            surfaceKind = NapaxiChannelSurfaceKind.IM,
            endpointKinds = endpointKinds,
            modalities = modalities,
            contentFormats = contentFormats,
            transport = transport,
            authRequirements = authRequirements,
            backgroundRequirements = backgroundRequirements,
            config = config,
        )
    }
}

public data class NapaxiChannelOutboundDeliveryResult(
    val delivered: Boolean,
    val receipt: JSONObject? = null,
    val error: String? = null,
) {
    public companion object {
        @JvmStatic
        public fun delivered(receipt: JSONObject = JSONObject()): NapaxiChannelOutboundDeliveryResult =
            NapaxiChannelOutboundDeliveryResult(delivered = true, receipt = receipt)

        @JvmStatic
        public fun failed(error: String): NapaxiChannelOutboundDeliveryResult =
            NapaxiChannelOutboundDeliveryResult(delivered = false, error = error)
    }
}

public data class NapaxiChannelProviderPumpResult(
    val channelName: String,
    val leased: Int,
    val delivered: Int,
    val failed: Int,
) {
    public val hadWork: Boolean get() = leased > 0
}

public object NapaxiChannelProviderEventType {
    public const val REGISTERED: String = "registered"
    public const val UNREGISTERED: String = "unregistered"
    public const val OUTBOUND_DELIVERED: String = "outbound_delivered"
    public const val OUTBOUND_FAILED: String = "outbound_failed"
}

public data class NapaxiChannelProviderEvent(
    val channelName: String,
    val providerId: String,
    val type: String,
    val outboundId: String? = null,
    val error: String? = null,
)

public interface NapaxiChannelProvider {
    public val manifest: NapaxiChannelProviderManifest

    public suspend fun start(context: NapaxiChannelProviderContext) {}

    public suspend fun stop() {}

    public suspend fun deliverOutbound(
        message: NapaxiChannelOutboundMessage,
    ): NapaxiChannelOutboundDeliveryResult
}

public class NapaxiChannelProviderContext internal constructor(
    private val queue: ChannelApi,
    public val manifest: NapaxiChannelProviderManifest,
) {
    public suspend fun submitInbound(
        message: NapaxiChannelInboundMessage,
    ): NapaxiChannelAcceptedReceipt = queue.submitInbound(message)

    public suspend fun submitTextInbound(
        peer: NapaxiChannelPeer,
        sender: NapaxiChannelActor,
        text: String,
        platformMessageId: String? = null,
        threadId: String? = null,
        raw: JSONObject? = null,
    ): NapaxiChannelAcceptedReceipt = submitInbound(
        NapaxiChannelInboundMessage(
            channelName = manifest.channelName,
            accountId = manifest.accountId,
            peer = peer,
            sender = sender,
            platformMessageId = platformMessageId,
            threadId = threadId,
            text = text,
            raw = raw,
        ),
    )

    public suspend fun leaseOutbound(limit: Int = 20): List<NapaxiChannelOutboundMessage> =
        queue.leaseOutbound(
            channelName = manifest.channelName,
            accountId = manifest.accountId,
            limit = limit,
        )

    public suspend fun ackOutbound(
        outboundId: String,
        receipt: JSONObject = JSONObject(),
    ): Boolean = queue.ackOutbound(outboundId, receipt)

    public suspend fun failOutbound(outboundId: String, error: String): Boolean =
        queue.failOutbound(outboundId, error)
}

public class NapaxiChannelProviderHost internal constructor(
    private val queue: ChannelApi,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val providers = LinkedHashMap<String, RegisteredChannelProvider>()
    private val eventFlow = MutableSharedFlow<NapaxiChannelProviderEvent>(extraBufferCapacity = 32)

    public val events: SharedFlow<NapaxiChannelProviderEvent> = eventFlow.asSharedFlow()

    public fun listProviderManifests(): List<NapaxiChannelProviderManifest> =
        providers.values.map { it.provider.manifest }

    public fun hasProvider(channelName: String): Boolean =
        providers.containsKey(channelName)

    public fun providerManifest(channelName: String): NapaxiChannelProviderManifest? =
        providers[channelName]?.provider?.manifest

    public suspend fun registerProvider(
        provider: NapaxiChannelProvider,
        autoPump: Boolean = false,
        pollIntervalMs: Long = 2_000,
    ) {
        val manifest = provider.manifest
        require(manifest.channelName.isNotBlank()) { "channelName must not be blank" }
        check(!providers.containsKey(manifest.channelName)) {
            "channel provider already registered: ${manifest.channelName}"
        }
        check(queue.register(manifest.toRegistration())) {
            "failed to register channel: ${manifest.channelName}"
        }
        val context = NapaxiChannelProviderContext(queue, manifest)
        try {
            provider.start(context)
        } catch (error: Throwable) {
            runCatching { queue.unregister(manifest.channelName) }
            throw error
        }
        val job = if (autoPump) {
            scope.launch {
                while (isActive) {
                    runCatching { pump(manifest.channelName) }
                    delay(pollIntervalMs)
                }
            }
        } else {
            null
        }
        providers[manifest.channelName] = RegisteredChannelProvider(provider, context, job)
        eventFlow.tryEmit(
            NapaxiChannelProviderEvent(
                channelName = manifest.channelName,
                providerId = manifest.providerId,
                type = NapaxiChannelProviderEventType.REGISTERED,
            ),
        )
    }

    public suspend fun pump(
        channelName: String,
        limit: Int = 20,
    ): NapaxiChannelProviderPumpResult {
        val registered = providers[channelName]
            ?: error("channel provider is not registered: $channelName")
        val outbound = registered.context.leaseOutbound(limit)
        var delivered = 0
        var failed = 0
        for (message in outbound) {
            val result = registered.provider.deliverOutbound(message)
            if (result.delivered) {
                registered.context.ackOutbound(message.id, result.receipt ?: JSONObject())
                delivered += 1
                eventFlow.tryEmit(
                    NapaxiChannelProviderEvent(
                        channelName = channelName,
                        providerId = registered.provider.manifest.providerId,
                        type = NapaxiChannelProviderEventType.OUTBOUND_DELIVERED,
                        outboundId = message.id,
                    ),
                )
            } else {
                registered.context.failOutbound(message.id, result.error ?: "delivery_failed")
                failed += 1
                eventFlow.tryEmit(
                    NapaxiChannelProviderEvent(
                        channelName = channelName,
                        providerId = registered.provider.manifest.providerId,
                        type = NapaxiChannelProviderEventType.OUTBOUND_FAILED,
                        outboundId = message.id,
                        error = result.error,
                    ),
                )
            }
        }
        return NapaxiChannelProviderPumpResult(
            channelName = channelName,
            leased = outbound.size,
            delivered = delivered,
            failed = failed,
        )
    }

    public suspend fun unregisterProvider(channelName: String) {
        val registered = providers.remove(channelName) ?: return
        registered.job?.cancel()
        registered.provider.stop()
        queue.unregister(channelName)
        eventFlow.tryEmit(
            NapaxiChannelProviderEvent(
                channelName = channelName,
                providerId = registered.provider.manifest.providerId,
                type = NapaxiChannelProviderEventType.UNREGISTERED,
            ),
        )
    }

    public fun dispose() {
        val registered = providers.values.toList()
        providers.clear()
        for (item in registered) {
            item.job?.cancel()
            scope.launch { item.provider.stop() }
        }
    }

    private data class RegisteredChannelProvider(
        val provider: NapaxiChannelProvider,
        val context: NapaxiChannelProviderContext,
        val job: kotlinx.coroutines.Job?,
    )
}
