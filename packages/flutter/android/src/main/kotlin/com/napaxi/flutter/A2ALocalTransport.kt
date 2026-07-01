package com.napaxi.flutter

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONObject

internal class A2ALocalTransport(
    private val appContext: Context,
    private val eventSinkProvider: () -> EventChannel.EventSink?
) {
    companion object {
        private const val TAG = "NapaxiA2ALocal"
        private const val SERVICE_TYPE = "_napaxi-a2a._tcp."
        private const val TRANSPORT = "lan_tcp_jsonl"
        private const val PREFERRED_LISTENER_PORT = 54509
        private const val SEND_CONNECT_TIMEOUT_MS = 2500
        private const val SEND_TOTAL_TIMEOUT_MS = 3000L
    }

    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val nsdManager: NsdManager? =
        appContext.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val wifiManager: WifiManager? =
        appContext.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val discoveredPeers = ConcurrentHashMap<String, MutableMap<String, Any>>()
    private val servicePeerIds = ConcurrentHashMap<String, String>()
    private val pendingEvents = CopyOnWriteArrayList<Map<String, Any>>()
    private val discoveryListeners = CopyOnWriteArrayList<NsdManager.DiscoveryListener>()
    private val discoveryGeneration = AtomicLong(0)
    private var serverSocket: ServerSocket? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var localPeerId: String = ""
    private var localAgentId: String = ""
    private var localDisplayName: String = ""
    private var localPublicKey: String = ""
    private var registeredName: String = ""
    private var sentMessageCount: Long = 0
    private var receivedMessageCount: Long = 0
    private var lastError: String = ""
    private var multicastLock: WifiManager.MulticastLock? = null
    @Volatile private var running = false

    fun status(): Map<String, Any> {
        val warnings = permissionWarnings()
        val reason = when {
            nsdManager == null -> "android_nsd_unavailable"
            warnings.isNotEmpty() -> warnings.joinToString(",")
            else -> ""
        }
        return mapOf(
            "supported" to (nsdManager != null),
            "running" to running,
            "transport" to TRANSPORT,
            "serviceType" to SERVICE_TYPE,
            "peerId" to localPeerId,
            "agentId" to localAgentId,
            "displayName" to localDisplayName,
            "endpoint" to localEndpoint(),
            "listenerPort" to (serverSocket?.localPort ?: 0),
            "registeredName" to registeredName,
            "discoveredPeerCount" to discoveredPeers.size,
            "activeDiscoveryCount" to discoveryListeners.size,
            "discoveryGeneration" to discoveryGeneration.get(),
            "sentMessageCount" to sentMessageCount,
            "receivedMessageCount" to receivedMessageCount,
            "multicastLockHeld" to (multicastLock?.isHeld == true),
            "permissionWarnings" to warnings,
            "lastError" to lastError,
            "reason" to reason
        )
    }

    fun start(args: Map<*, *>?): Map<String, Any> {
        val manager = nsdManager ?: return unsupported("android_nsd_unavailable")
        if (running) return status()
        blockingPermissionReason()?.let { return permissionUnavailable(it) }
        localPeerId = stringArg(args, "peerId").ifEmpty { stableLocalPeerId() }
        localAgentId = stringArg(args, "agentId")
        localDisplayName = stringArg(args, "displayName").ifEmpty { "Napaxi" }
        localPublicKey = stringArg(args, "publicKey")
        acquireMulticastLock()
        serverSocket = openServerSocket()
        running = true
        executor.execute { acceptLoop() }

        val info = NsdServiceInfo().apply {
            serviceName = safeServiceName(localDisplayName, localPeerId)
            serviceType = SERVICE_TYPE
            port = serverSocket?.localPort ?: 0
            setAttribute("peerId", localPeerId)
            setAttribute("agentId", localAgentId)
            setAttribute("displayName", localDisplayName)
            setAttribute("publicKey", localPublicKey)
            setAttribute("transport", TRANSPORT)
        }
        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registeredName = serviceInfo.serviceName ?: ""
                emit("a2aLocalTransportStarted", status())
            }

            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                lastError = "registration_failed:$errorCode"
                emitError("a2aLocalTransportError", "registration_failed", errorCode)
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                emit("a2aLocalTransportStopped", status())
            }

            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                lastError = "unregistration_failed:$errorCode"
                emitError("a2aLocalTransportError", "unregistration_failed", errorCode)
            }
        }
        manager.registerService(info, NsdManager.PROTOCOL_DNS_SD, registrationListener)
        return status()
    }

    fun stop(): Map<String, Any> {
        running = false
        discoveryListeners.forEach { listener ->
            try {
                nsdManager?.stopServiceDiscovery(listener)
            } catch (_: Exception) {
            }
        }
        discoveryListeners.clear()
        registrationListener?.let { listener ->
            try {
                nsdManager?.unregisterService(listener)
            } catch (_: Exception) {
            }
        }
        registrationListener = null
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
        releaseMulticastLock()
        return status()
    }

    fun discover(args: Map<*, *>?): Map<String, Any> {
        val manager = nsdManager ?: return unsupported("android_nsd_unavailable")
        blockingPermissionReason()?.let {
            return mapOf(
                "started" to false,
                "timeoutMs" to 0,
                "serviceType" to SERVICE_TYPE,
                "peers" to emptyList<Map<String, Any>>(),
                "generation" to discoveryGeneration.get(),
                "reason" to it
            )
        }
        val timeoutMs = longArg(args, "timeoutMs", 5000L).coerceIn(500L, 30000L)
        val generation = discoveryGeneration.incrementAndGet()
        discoveredPeers.clear()
        servicePeerIds.clear()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                emit("a2aLocalDiscoveryStarted", mapOf("serviceType" to regType, "generation" to generation))
            }

            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (!isA2AServiceType(serviceInfo.serviceType ?: "")) {
                    Log.d(TAG, "ignore service type=${serviceInfo.serviceType} name=${serviceInfo.serviceName}")
                    return
                }
                Log.d(TAG, "found service type=${serviceInfo.serviceType} name=${serviceInfo.serviceName} generation=$generation")
                manager.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        if (generation != discoveryGeneration.get()) return
                        lastError = "resolve_failed:$errorCode"
                        Log.d(TAG, "resolve failed code=$errorCode name=${serviceInfo.serviceName} generation=$generation")
                        emit("a2aLocalDiscoveryError", mapOf(
                            "code" to "resolve_failed",
                            "platformCode" to errorCode,
                            "serviceName" to (serviceInfo.serviceName ?: ""),
                            "generation" to generation
                        ))
                    }

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        if (generation != discoveryGeneration.get()) return
                        val peer = peerFromService(serviceInfo) ?: return
                        Log.d(TAG, "resolved peer=${peer["peerId"]} endpoint=${peer["endpoint"]} generation=$generation")
                        peer["generation"] = generation
                        peer["serviceName"] = serviceInfo.serviceName ?: ""
                        servicePeerIds[serviceInfo.serviceName ?: ""] = peer["peerId"].toString()
                        discoveredPeers[peer["peerId"].toString()] = peer
                        emit("a2aLocalPeerFound", peer)
                    }
                })
            }

            override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                val serviceName = serviceInfo.serviceName ?: ""
                servicePeerIds.remove(serviceName)?.let { discoveredPeers.remove(it) }
                emit("a2aLocalPeerLost", mapOf("serviceName" to serviceName, "generation" to generation))
            }

            override fun onDiscoveryStopped(serviceType: String) {
                emit("a2aLocalDiscoveryStopped", mapOf("serviceType" to serviceType, "generation" to generation))
            }

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                lastError = "start_failed:$errorCode"
                emit("a2aLocalDiscoveryError", mapOf(
                    "code" to "start_failed",
                    "platformCode" to errorCode,
                    "serviceType" to serviceType,
                    "generation" to generation
                ))
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                lastError = "stop_failed:$errorCode"
                emit("a2aLocalDiscoveryError", mapOf(
                    "code" to "stop_failed",
                    "platformCode" to errorCode,
                    "serviceType" to serviceType,
                    "generation" to generation
                ))
            }
        }
        discoveryListeners.add(listener)
        manager.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        executor.execute {
            Thread.sleep(timeoutMs)
            try {
                manager.stopServiceDiscovery(listener)
            } catch (_: Exception) {
            }
            discoveryListeners.remove(listener)
        }
        return mapOf(
            "started" to true,
            "timeoutMs" to timeoutMs,
            "serviceType" to SERVICE_TYPE,
            "generation" to generation,
            "peers" to discoveredPeers.values.toList()
        )
    }

    fun send(args: Map<*, *>?): Map<String, Any> {
        val endpoint = stringArg(args, "endpoint")
        val messageJson = stringArg(args, "messageJson")
        if (endpoint.isEmpty() || messageJson.isEmpty()) {
            return mapOf("sent" to false, "error" to "endpoint and messageJson are required")
        }
        val target = parseEndpoint(endpoint)
            ?: return mapOf("sent" to false, "error" to "unsupported endpoint: $endpoint")
        val future = executor.submit<Map<String, Any>> {
            try {
                Socket().use { socket ->
                    socket.connect(
                        InetSocketAddress(target.first, target.second),
                        SEND_CONNECT_TIMEOUT_MS
                    )
                    BufferedWriter(OutputStreamWriter(socket.getOutputStream(), Charsets.UTF_8)).use { writer ->
                        writer.write(messageJson)
                        writer.newLine()
                        writer.flush()
                    }
                }
                sentMessageCount += 1
                emit("a2aLocalMessageSent", mapOf("endpoint" to endpoint))
                mapOf("sent" to true, "endpoint" to endpoint)
            } catch (error: Exception) {
                lastError = error.message ?: "send_failed"
                emit("a2aLocalSendFailed", mapOf("endpoint" to endpoint, "error" to lastError))
                mapOf("sent" to false, "endpoint" to endpoint, "error" to lastError)
            }
        }
        return try {
            future.get(SEND_TOTAL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (error: Exception) {
            future.cancel(true)
            lastError = error.message ?: "send_timeout"
            emit("a2aLocalSendFailed", mapOf("endpoint" to endpoint, "error" to lastError))
            mapOf("sent" to false, "endpoint" to endpoint, "error" to lastError)
        }
    }

    fun drainEvents(): List<Map<String, Any>> {
        val drained = pendingEvents.toList()
        pendingEvents.clear()
        return drained
    }

    private fun acceptLoop() {
        val socket = serverSocket ?: return
        while (running) {
            try {
                val client = socket.accept()
                executor.execute { readClient(client) }
            } catch (_: Exception) {
                if (running) {
                    lastError = "accept_failed"
                    emitError("a2aLocalTransportError", "accept_failed", -1)
                }
            }
        }
    }

    private fun readClient(client: Socket) {
        client.use { socket ->
            val remote = socket.inetAddress?.hostAddress ?: ""
            BufferedReader(InputStreamReader(socket.getInputStream(), Charsets.UTF_8)).use { reader ->
                var line = reader.readLine()
                while (line != null) {
                    if (line.isNotBlank()) {
                        receivedMessageCount += 1
                        emit("a2aLocalPeerMessage", mapOf("messageJson" to line, "source" to "lan_tcp_jsonl", "remoteAddress" to remote))
                    }
                    line = reader.readLine()
                }
            }
        }
    }

    private fun peerFromService(serviceInfo: NsdServiceInfo): MutableMap<String, Any>? {
        val host = serviceInfo.host?.hostAddress ?: return null
        val port = serviceInfo.port
        if (port <= 0) return null
        val peerId = attr(serviceInfo, "peerId").ifEmpty { serviceInfo.serviceName ?: "" }
        if (peerId.isEmpty() || peerId == localPeerId) return null
        return mutableMapOf(
            "peerId" to peerId,
            "agentId" to attr(serviceInfo, "agentId"),
            "displayName" to attr(serviceInfo, "displayName").ifEmpty { serviceInfo.serviceName ?: peerId },
            "publicKey" to attr(serviceInfo, "publicKey"),
            "transport" to TRANSPORT,
            "endpoint" to "tcp://${formatEndpointHost(host)}:$port/a2a",
            "host" to host,
            "port" to port
        )
    }

    private fun localEndpoint(): String {
        val port = serverSocket?.localPort ?: 0
        val host = reachableLocalHost()
        return if (running && port > 0 && host.isNotEmpty()) {
            "tcp://${formatEndpointHost(host)}:$port/a2a"
        } else {
            ""
        }
    }

    private fun openServerSocket(): ServerSocket {
        return try {
            ServerSocket(PREFERRED_LISTENER_PORT)
        } catch (error: Exception) {
            lastError = "preferred_port_unavailable:${error.message ?: error.javaClass.simpleName}"
            ServerSocket(0)
        }
    }

    private fun emit(action: String, payload: Map<String, Any>) {
        val event = mapOf("action" to action, "payload" to JSONObject(payload).toString())
        pendingEvents.add(event)
        if (pendingEvents.size > 200) {
            pendingEvents.removeAt(0)
        }
        mainHandler.post {
            eventSinkProvider()?.success(event)
        }
    }

    private fun emitError(action: String, code: String, platformCode: Int) {
        emit(action, mapOf("code" to code, "platformCode" to platformCode))
    }

    private fun unsupported(reason: String): Map<String, Any> = mapOf(
        "supported" to false,
        "running" to false,
        "transport" to TRANSPORT,
        "serviceType" to SERVICE_TYPE,
        "listenerPort" to 0,
        "registeredName" to "",
        "discoveredPeerCount" to 0,
        "activeDiscoveryCount" to 0,
        "discoveryGeneration" to discoveryGeneration.get(),
        "sentMessageCount" to sentMessageCount,
        "receivedMessageCount" to receivedMessageCount,
        "multicastLockHeld" to false,
        "lastError" to reason,
        "reason" to reason
    )

    private fun permissionUnavailable(reason: String): Map<String, Any> = mapOf(
        "supported" to true,
        "running" to false,
        "transport" to TRANSPORT,
        "serviceType" to SERVICE_TYPE,
        "peerId" to localPeerId,
        "agentId" to localAgentId,
        "displayName" to localDisplayName,
        "endpoint" to "",
        "listenerPort" to 0,
        "registeredName" to "",
        "discoveredPeerCount" to discoveredPeers.size,
        "activeDiscoveryCount" to discoveryListeners.size,
        "discoveryGeneration" to discoveryGeneration.get(),
        "sentMessageCount" to sentMessageCount,
        "receivedMessageCount" to receivedMessageCount,
        "multicastLockHeld" to false,
        "permissionWarnings" to permissionWarnings(),
        "lastError" to reason,
        "reason" to reason
    )

    private fun acquireMulticastLock() {
        val manager = wifiManager ?: return
        if (multicastLock?.isHeld == true) return
        try {
            multicastLock = manager.createMulticastLock("napaxi-a2a-local").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (error: Exception) {
            lastError = "multicast_lock_failed:${error.message ?: error.javaClass.simpleName}"
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (error: Exception) {
            lastError = "multicast_unlock_failed:${error.message ?: error.javaClass.simpleName}"
        } finally {
            multicastLock = null
        }
    }

    private fun permissionWarnings(): List<String> {
        val warnings = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 33 &&
            appContext.checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED
        ) {
            warnings += "android_nearby_wifi_devices_permission_missing"
        }
        if (appContext.checkSelfPermission(Manifest.permission.ACCESS_WIFI_STATE) != PackageManager.PERMISSION_GRANTED) {
            warnings += "android_access_wifi_state_permission_missing"
        }
        return warnings
    }

    private fun blockingPermissionReason(): String? {
        if (Build.VERSION.SDK_INT >= 33 &&
            appContext.checkSelfPermission(Manifest.permission.NEARBY_WIFI_DEVICES) != PackageManager.PERMISSION_GRANTED
        ) {
            return "android_nearby_wifi_devices_permission_missing"
        }
        return null
    }

    private fun parseEndpoint(endpoint: String): Pair<String, Int>? {
        val clean = endpoint.removePrefix("tcp://").removePrefix("jsonl://").removeSuffix("/a2a")
        if (clean.startsWith("[")) {
            val hostEnd = clean.indexOf(']')
            if (hostEnd <= 1 || clean.getOrNull(hostEnd + 1) != ':') return null
            val port = clean.substring(hostEnd + 2).toIntOrNull() ?: return null
            return clean.substring(1, hostEnd) to port
        }
        val separator = clean.lastIndexOf(':')
        if (separator <= 0 || separator >= clean.length - 1) return null
        val port = clean.substring(separator + 1).toIntOrNull() ?: return null
        return clean.substring(0, separator) to port
    }

    private fun reachableLocalHost(): String {
        wifiAddress()?.let { return it }
        return networkInterfaceAddress()
    }

    private fun wifiAddress(): String? {
        return try {
            val ip = wifiManager?.connectionInfo?.ipAddress ?: 0
            if (ip == 0) return null
            val octets = listOf(
                ip and 0xff,
                ip shr 8 and 0xff,
                ip shr 16 and 0xff,
                ip shr 24 and 0xff
            )
            octets.joinToString(".").takeIf { it != "0.0.0.0" }
        } catch (_: Exception) {
            null
        }
    }

    private fun networkInterfaceAddress(): String {
        return try {
            NetworkInterface.getNetworkInterfaces()
                ?.asSequence()
                ?.filter { it.isUp && !it.isLoopback }
                ?.flatMap { it.inetAddresses.asSequence() }
                ?.firstOrNull { address ->
                    !address.isAnyLocalAddress &&
                        !address.isLoopbackAddress &&
                        !address.isLinkLocalAddress &&
                        address.hostAddress?.contains(":") == false
                }
                ?.hostAddress
                ?: ""
        } catch (_: Exception) {
            ""
        }
    }

    private fun formatEndpointHost(host: String): String {
        return if (host.contains(":") && !host.startsWith("[")) "[$host]" else host
    }

    private fun isA2AServiceType(value: String): Boolean {
        return value.trim().trimEnd('.') == SERVICE_TYPE.trimEnd('.')
    }

    private fun attr(serviceInfo: NsdServiceInfo, key: String): String {
        val raw = serviceInfo.attributes?.get(key) ?: return ""
        return String(raw, Charsets.UTF_8)
    }

    private fun stableLocalPeerId(): String {
        val prefs = appContext.getSharedPreferences("napaxi_a2a_local", Context.MODE_PRIVATE)
        val existing = prefs.getString("peer_id", null)
        if (!existing.isNullOrEmpty()) return existing
        val created = "android-${UUID.randomUUID()}"
        prefs.edit().putString("peer_id", created).apply()
        return created
    }

    private fun safeServiceName(displayName: String, peerId: String): String {
        val base = (displayName.ifEmpty { "Napaxi" }).replace(Regex("[^A-Za-z0-9_-]"), "-")
        return "$base-${peerId.takeLast(8)}".take(40)
    }

    private fun stringArg(args: Map<*, *>?, key: String): String =
        args?.get(key)?.toString() ?: ""

    private fun longArg(args: Map<*, *>?, key: String, default: Long): Long =
        args?.get(key)?.toString()?.toLongOrNull() ?: default
}
