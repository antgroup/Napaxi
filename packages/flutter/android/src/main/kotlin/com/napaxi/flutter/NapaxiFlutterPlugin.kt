package com.napaxi.flutter

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.ClipData
import android.content.ContentUris
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.content.res.AssetManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

/// Flutter plugin for Napaxi background service management.
///
/// Provides a MethodChannel for controlling the foreground service
/// and an EventChannel for receiving notification action callbacks.
class NapaxiFlutterPlugin : FlutterPlugin, MethodCallHandler, StreamHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener, PluginRegistry.ActivityResultListener,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var platformContextChannel: MethodChannel
    private lateinit var mediaLibraryChannel: MethodChannel
    private lateinit var sandboxPtyChannel: MethodChannel
    private lateinit var sandboxPtyEventChannel: EventChannel
    private lateinit var bluetoothHeadsetChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var sandboxPtyEventSink: EventChannel.EventSink? = null
    private var context: Context? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingNotificationPermissionResult: Result? = null
    private var pendingLocationPermissionResult: Result? = null
    private var pendingA2ALocalPermissionResult: Result? = null
    private var pendingMediaLibraryPermissionCall: MethodCall? = null
    private var pendingMediaLibraryPermissionResult: Result? = null
    private var pendingMicrophonePermissionResult: Result? = null
    private var pendingApkInstallPath: String? = null
    private var pendingApkInstallResult: Result? = null
    private var pendingProviderInstallResult: Result? = null
    private var pendingProviderInstall: Map<String, String>? = null
    private var pendingAgentTrigger: Map<String, String>? = null
    private var pendingA2ADeepLink: Map<String, String>? = null
    private var pendingAgentActionResult: Result? = null
    private var pendingAgentActionRequestId: String? = null
    private var a2aLocalTransport: A2ALocalTransport? = null
    private val sandboxPtySessions = ConcurrentHashMap<Long, Thread>()
    private var pendingSpeechRecognitionResult: Result? = null
    private var currentSpeechRecognizer: SpeechRecognizer? = null
    private var currentSpeechTimeout: Runnable? = null
    private var currentSpeechStartedAtMs: Long = 0L
    private var currentSpeechAudioRoute: BluetoothSpeechAudioRoute? = null
    private var bluetoothTextToSpeech: TextToSpeech? = null
    private var pendingTtsResult: Result? = null
    private var pendingTtsUtteranceId: String? = null

    companion object {
        const val METHOD_CHANNEL = "com.napaxi.flutter/background"
        const val PLATFORM_CONTEXT_CHANNEL = "com.napaxi.flutter/platform_context"
        const val MEDIA_LIBRARY_CHANNEL = "com.napaxi.flutter/media_library"
        const val SANDBOX_PTY_CHANNEL = "com.napaxi.flutter/sandbox_pty"
        const val SANDBOX_PTY_EVENT_CHANNEL = "com.napaxi.flutter/sandbox_pty_events"
        const val BLUETOOTH_HEADSET_CHANNEL = "com.napaxi.flutter/bluetooth_headset"
        const val EVENT_CHANNEL = "com.napaxi.flutter/background_events"
        const val BLUETOOTH_HEADSET_TAG = "NapaxiBluetoothHeadset"

        // Method names
        const val METHOD_GET_PLATFORM_CONTEXT = "getPlatformContext"
        const val METHOD_EXECUTE_LINUX_PROGRAM = "executeLinuxProgram"
        const val METHOD_LIST_BLUETOOTH_AUDIO_DEVICES = "listAudioDevices"
        const val METHOD_CHECK_MICROPHONE_PERMISSION = "checkMicrophonePermission"
        const val METHOD_REQUEST_MICROPHONE_PERMISSION = "requestMicrophonePermission"
        const val METHOD_CAPTURE_BLUETOOTH_TRANSCRIPT = "captureSpeechTranscript"
        const val METHOD_SPEAK_BLUETOOTH_REPLY = "speakBluetoothReply"
        const val METHOD_START = "startForegroundService"
        const val METHOD_STOP = "stopForegroundService"
        const val METHOD_UPDATE_NOTIFICATION = "updateNotification"
        const val METHOD_SHOW_HITL = "showHitlNotification"
        const val METHOD_SHOW_COMPLETION = "showCompletionNotification"
        const val METHOD_SHOW_ERROR = "showErrorNotification"
        const val METHOD_CANCEL_NOTIFICATION = "cancelNotification"
        const val METHOD_CHECK_NOTIFICATION_PERMISSION = "checkNotificationPermission"
        const val METHOD_REQUEST_NOTIFICATION_PERMISSION = "requestNotificationPermission"
        const val METHOD_REQUEST_LOCATION_PERMISSION = "requestLocationPermission"
        const val METHOD_INSTALL_APK = "installApk"
        const val METHOD_OPEN_FILE = "openFile"
        const val METHOD_LIST_AGENT_PROVIDERS = "listAgentProviders"
        const val METHOD_REQUEST_AGENT_PROVIDER_INSTALL = "requestAgentProviderInstall"
        const val METHOD_GET_PENDING_PROVIDER_INSTALL_REQUEST = "getPendingProviderInstallRequest"
        const val METHOD_CLEAR_PENDING_PROVIDER_INSTALL_REQUEST = "clearPendingProviderInstallRequest"
        const val METHOD_GET_PENDING_AGENT_TRIGGER_REQUEST = "getPendingAgentTriggerRequest"
        const val METHOD_CLEAR_PENDING_AGENT_TRIGGER_REQUEST = "clearPendingAgentTriggerRequest"
        const val METHOD_GET_PENDING_A2A_DEEP_LINK = "getPendingA2ADeepLink"
        const val METHOD_CLEAR_PENDING_A2A_DEEP_LINK = "clearPendingA2ADeepLink"
        const val METHOD_A2A_LOCAL_TRANSPORT_STATUS = "a2aLocalTransportStatus"
        const val METHOD_CHECK_A2A_LOCAL_PERMISSION = "checkA2ALocalPermission"
        const val METHOD_REQUEST_A2A_LOCAL_PERMISSION = "requestA2ALocalPermission"
        const val METHOD_START_A2A_LOCAL_TRANSPORT = "startA2ALocalTransport"
        const val METHOD_STOP_A2A_LOCAL_TRANSPORT = "stopA2ALocalTransport"
        const val METHOD_DISCOVER_A2A_LOCAL_PEERS = "discoverA2ALocalPeers"
        const val METHOD_SEND_A2A_LOCAL_MESSAGE = "sendA2ALocalMessage"
        const val METHOD_DRAIN_A2A_LOCAL_TRANSPORT_EVENTS = "drainA2ALocalTransportEvents"
        const val METHOD_GET_AGENT_PROVIDER_HOST_PACKAGE_NAME = "getAgentProviderHostPackageName"
        const val METHOD_GET_AGENT_PROVIDER_HOST_INFO = "getAgentProviderHostInfo"
        const val METHOD_EXECUTE_AGENT_PROVIDER_ACTION = "executeAgentProviderAction"
        const val METHOD_SCHEDULE_AUTOMATION_WAKE = "scheduleAutomationWake"
        const val METHOD_CANCEL_AUTOMATION_WAKE = "cancelAutomationWake"
        const val METHOD_GET_AUTOMATION_SCHEDULER_STATUS = "getAutomationSchedulerStatus"
        const val METHOD_GET_PENDING_AUTOMATION_WAKES = "getPendingAutomationWakes"
        const val METHOD_CLEAR_PENDING_AUTOMATION_WAKE = "clearPendingAutomationWake"
        const val REQUEST_POST_NOTIFICATIONS = 4201
        const val REQUEST_INSTALL_UNKNOWN_APPS = 4202
        const val REQUEST_AGENT_PROVIDER_INSTALL = 4203
        const val REQUEST_AGENT_PROVIDER_ACTION = 4204
        const val REQUEST_LOCATION_PERMISSION = 4205
        const val REQUEST_A2A_LOCAL_PERMISSION = 4206
        const val REQUEST_MEDIA_LIBRARY_PERMISSION = 4207
        const val REQUEST_MICROPHONE_PERMISSION = 4208
        const val ACTION_INSTALL_AGENT = "agent.provider.action.INSTALL_AGENT"
        const val ACTION_HANDLE_PROPOSAL = "agent.provider.action.HANDLE_PROPOSAL"
        const val ACTION_HOST_INSTALL_PROVIDER_AGENT = "agent.host.action.INSTALL_PROVIDER_AGENT"
        const val ACTION_HOST_TRIGGER_AGENT = "agent.host.action.TRIGGER_AGENT"
        const val ACTION_HOST_A2A_DEEP_LINK = "agent.host.action.A2A_DEEP_LINK"
        const val EXTRA_INSTALL_REQUEST_JSON = "agent.provider.extra.INSTALL_REQUEST_JSON"
        const val EXTRA_INSTALL_RESULT_JSON = "agent.provider.extra.INSTALL_RESULT_JSON"
        const val EXTRA_TRIGGER_REQUEST_JSON = "agent.provider.extra.TRIGGER_REQUEST_JSON"
        const val EXTRA_PACKAGE_JSON = "agent.provider.extra.PACKAGE_JSON"
        const val EXTRA_ACTION_JSON = "agent.provider.extra.ACTION_JSON"
        const val EXTRA_PROPOSAL_JSON = "agent.provider.extra.PROPOSAL_JSON"
        const val EXTRA_RESULT_JSON = "agent.provider.extra.RESULT_JSON"
        const val EXTRA_A2A_ENVELOPE_JSON = "agent.a2a.extra.ENVELOPE_JSON"

        init {
            System.loadLibrary("napaxi_api_bridge")
        }
    }

    private external fun registerAssetManager(assetManager: AssetManager)
    private external fun executeLinuxProgram(requestJson: String): String
    private external fun openLinuxPtySession(requestJson: String): String
    private external fun writeLinuxPtySession(sessionId: Long, data: String): String
    private external fun resizeLinuxPtySession(sessionId: Long, cols: Int, rows: Int): String
    private external fun closeLinuxPtySession(sessionId: Long): String
    private external fun drainLinuxPtyEvents(sessionId: Long): String

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        registerAssetManager(binding.applicationContext.assets)

        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        channel.setMethodCallHandler(this)
        a2aLocalTransport = A2ALocalTransport(binding.applicationContext) { eventSink }

        mediaLibraryChannel = MethodChannel(binding.binaryMessenger, MEDIA_LIBRARY_CHANNEL)
        mediaLibraryChannel.setMethodCallHandler(::handleMediaLibraryCall)

        platformContextChannel = MethodChannel(binding.binaryMessenger, PLATFORM_CONTEXT_CHANNEL)
        platformContextChannel.setMethodCallHandler { call, result ->
            val ctx = context ?: run {
                result.error("UNAVAILABLE", "Context not available", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                METHOD_GET_PLATFORM_CONTEXT -> {
                    try {
                        result.success(mapOf(
                            "platform" to "android",
                            "filesDir" to ctx.filesDir.absolutePath,
                            "nativeLibraryDir" to ctx.applicationInfo.nativeLibraryDir,
                            "userTimezone" to TimeZone.getDefault().id,
                        ))
                    } catch (e: Exception) {
                        result.error("PLATFORM_CONTEXT_FAILED", e.message, null)
                    }
                }
                METHOD_EXECUTE_LINUX_PROGRAM -> {
                    runLinuxProgram(ctx, call, result)
                }
                else -> result.notImplemented()
            }
        }

        sandboxPtyChannel = MethodChannel(binding.binaryMessenger, SANDBOX_PTY_CHANNEL)
        sandboxPtyChannel.setMethodCallHandler { call, result ->
            val ctx = context ?: run {
                result.error("UNAVAILABLE", "Context not available", null)
                return@setMethodCallHandler
            }
            handleSandboxPtyCall(ctx, call, result)
        }

        sandboxPtyEventChannel = EventChannel(binding.binaryMessenger, SANDBOX_PTY_EVENT_CHANNEL)
        sandboxPtyEventChannel.setStreamHandler(object : StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sandboxPtyEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                sandboxPtyEventSink = null
            }
        })

        bluetoothHeadsetChannel = MethodChannel(
            binding.binaryMessenger,
            BLUETOOTH_HEADSET_CHANNEL
        )
        bluetoothHeadsetChannel.setMethodCallHandler { call, result ->
            val ctx = context ?: run {
                result.error("UNAVAILABLE", "Context not available", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                METHOD_LIST_BLUETOOTH_AUDIO_DEVICES -> {
                    listBluetoothAudioDevices(ctx) { payload ->
                        result.success(payload)
                    }
                }
                METHOD_CHECK_MICROPHONE_PERMISSION -> {
                    result.success(hasMicrophonePermission(ctx))
                }
                METHOD_REQUEST_MICROPHONE_PERMISSION -> {
                    requestMicrophonePermission(ctx, result)
                }
                METHOD_CAPTURE_BLUETOOTH_TRANSCRIPT -> {
                    captureBluetoothTranscript(ctx, call, result)
                }
                METHOD_SPEAK_BLUETOOTH_REPLY -> {
                    speakBluetoothReply(ctx, call, result)
                }
                else -> result.notImplemented()
            }
        }

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)

        NapaxiActionReceiver.setActionCallback { action, requestId, payload ->
            eventSink?.success(mapOf(
                "action" to action,
                "requestId" to requestId,
                "payload" to payload,
            ))
        }
        NapaxiAutomationScheduler.setWakeCallback { wake ->
            eventSink?.success(mapOf(
                "action" to "automationWake",
                "payload" to JSONObject(wake).toString(),
            ))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        platformContextChannel.setMethodCallHandler(null)
        mediaLibraryChannel.setMethodCallHandler(null)
        sandboxPtyChannel.setMethodCallHandler(null)
        sandboxPtyEventChannel.setStreamHandler(null)
        bluetoothHeadsetChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        closeAllSandboxPtySessions()
        NapaxiAutomationScheduler.clearWakeCallback()
        a2aLocalTransport?.stop()
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        context = null
        eventSink = null
        sandboxPtyEventSink = null
        pendingNotificationPermissionResult = null
        pendingLocationPermissionResult = null
        pendingA2ALocalPermissionResult = null
        pendingMediaLibraryPermissionCall = null
        pendingMediaLibraryPermissionResult = null
        pendingMicrophonePermissionResult = null
        pendingApkInstallPath = null
        pendingApkInstallResult = null
        pendingProviderInstallResult = null
        pendingProviderInstall = null
        pendingAgentTrigger = null
        pendingA2ADeepLink = null
        pendingAgentActionResult = null
        pendingAgentActionRequestId = null
        cleanupSpeechRecognition()
        finishTtsError("UNAVAILABLE", "Flutter engine detached.", null)
        a2aLocalTransport = null
    }

    private fun runLinuxProgram(ctx: Context, call: MethodCall, result: Result) {
        val workspaceDir = call.argument<String>("workspaceDir") ?: ""
        val argv = call.argument<List<Any>>("argv") ?: emptyList()
        if (workspaceDir.isBlank()) {
            result.error("INVALID_ARGS", "workspaceDir is required", null)
            return
        }
        if (argv.isEmpty()) {
            result.error("INVALID_ARGS", "argv is required", null)
            return
        }
        val request = JSONObject().apply {
            put("files_dir", ctx.filesDir.absolutePath)
            put("native_library_dir", ctx.applicationInfo.nativeLibraryDir)
            put("workspace_dir", workspaceDir)
            put("argv", JSONArray().also { array ->
                argv.forEach { item -> array.put(item.toString()) }
            })
            put("workdir", call.argument<String>("workdir") ?: "/workspace")
            put("timeout", call.argument<Int>("timeout") ?: 120)
        }
        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            try {
                val response = executeLinuxProgram(request.toString())
                mainHandler.post { result.success(response) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("LINUX_PROGRAM_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun handleSandboxPtyCall(ctx: Context, call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> result.success(null)
            "getWorkspaceHostPath" -> result.success(defaultSandboxWorkspaceDir(ctx).absolutePath)
            "openSession" -> openSandboxPtySession(ctx, call, result)
            "writeSession" -> {
                val sessionId = call.argument<Number>("sessionId")?.toLong()
                val data = call.argument<String>("data")
                if (sessionId == null || data == null) {
                    result.error("INVALID_ARGS", "sessionId and data required", null)
                    return
                }
                Thread {
                    val response = writeLinuxPtySession(sessionId, data)
                    postJsonSuccessOrError(result, response, "WRITE_FAILED")
                }.start()
            }
            "resizeSession" -> {
                val sessionId = call.argument<Number>("sessionId")?.toLong()
                val cols = call.argument<Int>("cols")
                val rows = call.argument<Int>("rows")
                if (sessionId == null || cols == null || rows == null) {
                    result.error("INVALID_ARGS", "sessionId, cols, rows required", null)
                    return
                }
                Thread {
                    val response = resizeLinuxPtySession(sessionId, cols, rows)
                    postJsonSuccessOrError(result, response, "RESIZE_FAILED")
                }.start()
            }
            "closeSession" -> {
                val sessionId = call.argument<Number>("sessionId")?.toLong()
                if (sessionId == null) {
                    result.error("INVALID_ARGS", "sessionId required", null)
                    return
                }
                closeSandboxPtySession(sessionId)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openSandboxPtySession(ctx: Context, call: MethodCall, result: Result) {
        val workspaceDir = call.argument<String>("workspaceDir")
            ?.takeIf { it.isNotBlank() }
            ?: defaultSandboxWorkspaceDir(ctx).absolutePath
        val argv = call.argument<List<Any>>("argv")
            ?.map { it.toString() }
            ?.takeIf { it.isNotEmpty() }
            ?: listOf("/bin/sh")
        val request = JSONObject().apply {
            put("files_dir", ctx.filesDir.absolutePath)
            put("native_library_dir", ctx.applicationInfo.nativeLibraryDir)
            put("workspace_dir", workspaceDir)
            put("argv", JSONArray().also { array -> argv.forEach { array.put(it) } })
            put("workdir", call.argument<String>("workdir") ?: "/workspace")
            put("cols", call.argument<Int>("cols") ?: 80)
            put("rows", call.argument<Int>("rows") ?: 24)
        }

        Thread {
            try {
                val response = JSONObject(openLinuxPtySession(request.toString()))
                if (!response.optBoolean("success", false)) {
                    postResultError(result, "OPEN_SESSION_FAILED", response.optString("error"))
                    return@Thread
                }
                val sessionId = response.optLong("sessionId")
                Handler(Looper.getMainLooper()).post {
                    result.success(sessionId)
                    startSandboxPtyEventPump(sessionId)
                }
            } catch (e: Exception) {
                postResultError(result, "OPEN_SESSION_FAILED", e.message)
            }
        }.start()
    }

    private fun defaultSandboxWorkspaceDir(ctx: Context): File {
        val dir = File(ctx.filesDir, "linux-env/workspace")
        if (!dir.exists()) {
            dir.mkdirs()
        }
        return dir
    }

    private fun startSandboxPtyEventPump(sessionId: Long) {
        if (sandboxPtySessions.containsKey(sessionId)) return
        val running = AtomicBoolean(true)
        val thread = Thread {
            while (running.get()) {
                try {
                    val response = JSONObject(drainLinuxPtyEvents(sessionId))
                    val events = response.optJSONArray("events") ?: JSONArray()
                    for (i in 0 until events.length()) {
                        val event = events.optJSONObject(i) ?: continue
                        val kind = event.optString("kind")
                        postSandboxPtyEvent(event)
                        if (kind == "SessionExit" || kind == "SessionClosed") {
                            running.set(false)
                        }
                    }
                } catch (e: Exception) {
                    sandboxPtyEventSink?.error("EVENTS_ERROR", e.message, null)
                    running.set(false)
                }
                if (running.get()) {
                    try {
                        Thread.sleep(30)
                    } catch (_: InterruptedException) {
                        running.set(false)
                    }
                }
            }
            sandboxPtySessions.remove(sessionId)
        }
        sandboxPtySessions[sessionId] = thread
        thread.start()
    }

    private fun postSandboxPtyEvent(event: JSONObject) {
        val payload = mutableMapOf<String, Any?>(
            "sessionId" to event.optLong("sessionId"),
            "kind" to event.optString("kind"),
        )
        if (event.has("data")) payload["data"] = event.optString("data")
        if (!event.isNull("exitCode")) payload["exitCode"] = event.optInt("exitCode")
        Handler(Looper.getMainLooper()).post {
            sandboxPtyEventSink?.success(payload)
        }
    }

    private fun closeSandboxPtySession(sessionId: Long) {
        sandboxPtySessions.remove(sessionId)?.interrupt()
        Thread {
            closeLinuxPtySession(sessionId)
        }.start()
    }

    private fun closeAllSandboxPtySessions() {
        sandboxPtySessions.keys.toList().forEach { closeSandboxPtySession(it) }
        sandboxPtySessions.clear()
    }

    private fun postJsonSuccessOrError(result: Result, responseJson: String, errorCode: String) {
        try {
            val response = JSONObject(responseJson)
            if (response.optBoolean("success", false)) {
                Handler(Looper.getMainLooper()).post { result.success(null) }
            } else {
                postResultError(result, errorCode, response.optString("error"))
            }
        } catch (e: Exception) {
            postResultError(result, errorCode, e.message)
        }
    }

    private fun postResultError(result: Result, code: String, message: String?) {
        Handler(Looper.getMainLooper()).post {
            result.error(code, message ?: code, null)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
        binding.addOnNewIntentListener(this)
        captureAgentTrigger(binding.activity.intent)
        captureA2ADeepLink(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val ctx = context ?: run {
            result.error("UNAVAILABLE", "Context not available", null)
            return
        }

        when (call.method) {
            METHOD_START -> {
                val config = call.arguments as? Map<*, *>
                startService(ctx, config)
                result.success(true)
            }
            METHOD_STOP -> {
                NapaxiAgentService.stop(ctx)
                result.success(true)
            }
            METHOD_UPDATE_NOTIFICATION -> {
                val message = call.argument<String>("message")
                val progress = call.argument<Int>("progress")
                NapaxiNotificationManager.updateOngoingNotification(ctx, message, progress)
                result.success(true)
            }
            METHOD_SHOW_HITL -> {
                val requestId = call.argument<String>("requestId") ?: ""
                val question = call.argument<String>("question") ?: ""
                val options = call.argument<List<String>>("options") ?: emptyList()
                NapaxiNotificationManager.showHitlNotification(ctx, requestId, question, options)
                result.success(true)
            }
            METHOD_SHOW_COMPLETION -> {
                val title = call.argument<String>("title") ?: "Napaxi Agent"
                val message = call.argument<String>("message") ?: "Task completed"
                NapaxiNotificationManager.showCompletionNotification(ctx, title, message)
                result.success(true)
            }
            METHOD_SHOW_ERROR -> {
                val title = call.argument<String>("title") ?: "Napaxi Agent"
                val message = call.argument<String>("message") ?: "Error occurred"
                NapaxiNotificationManager.showErrorNotification(ctx, title, message)
                result.success(true)
            }
            METHOD_CANCEL_NOTIFICATION -> {
                val notificationId = call.argument<Int>("notificationId")
                if (notificationId != null) {
                    NapaxiNotificationManager.cancelNotification(ctx, notificationId)
                } else {
                    NapaxiNotificationManager.cancelAllNotifications(ctx)
                }
                result.success(true)
            }
            METHOD_CHECK_NOTIFICATION_PERMISSION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                } else {
                    result.success(true)
                }
            }
            METHOD_REQUEST_NOTIFICATION_PERMISSION -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    val granted = ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                        return
                    }
                    val activity = activityBinding?.activity
                    if (activity == null) {
                        result.success(false)
                        return
                    }
                    if (pendingNotificationPermissionResult != null) {
                        result.error("IN_PROGRESS", "Notification permission request already in progress", null)
                        return
                    }
                    pendingNotificationPermissionResult = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        REQUEST_POST_NOTIFICATIONS
                    )
                } else {
                    result.success(true)
                }
            }
            METHOD_REQUEST_LOCATION_PERMISSION -> {
                requestLocationPermission(ctx, result)
            }
            METHOD_INSTALL_APK -> {
                val apkPath = call.argument<String>("apkPath") ?: ""
                installApk(ctx, apkPath, result)
            }
            METHOD_OPEN_FILE -> {
                val path = call.argument<String>("path") ?: ""
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
                openFile(ctx, path, mimeType, result)
            }
            METHOD_LIST_AGENT_PROVIDERS -> {
                result.success(listAgentProviders(ctx))
            }
            METHOD_REQUEST_AGENT_PROVIDER_INSTALL -> {
                val provider = call.argument<Map<String, Any>>("provider")
                val requestJson = call.argument<String>("requestJson") ?: ""
                requestAgentProviderInstall(ctx, provider, requestJson, result)
            }
            METHOD_GET_PENDING_PROVIDER_INSTALL_REQUEST -> {
                result.success(getPendingProviderInstallRequest())
            }
            METHOD_CLEAR_PENDING_PROVIDER_INSTALL_REQUEST -> {
                clearPendingProviderInstallRequest()
                result.success(true)
            }
            METHOD_GET_PENDING_AGENT_TRIGGER_REQUEST -> {
                result.success(getPendingAgentTriggerRequest())
            }
            METHOD_CLEAR_PENDING_AGENT_TRIGGER_REQUEST -> {
                clearPendingAgentTriggerRequest()
                result.success(true)
            }
            METHOD_GET_PENDING_A2A_DEEP_LINK -> {
                result.success(getPendingA2ADeepLink())
            }
            METHOD_CLEAR_PENDING_A2A_DEEP_LINK -> {
                clearPendingA2ADeepLink()
                result.success(true)
            }
            METHOD_A2A_LOCAL_TRANSPORT_STATUS -> {
                result.success(a2aLocalTransport?.status() ?: mapOf(
                    "supported" to false,
                    "running" to false,
                    "reason" to "transport_not_initialized"
                ))
            }
            METHOD_CHECK_A2A_LOCAL_PERMISSION -> {
                result.success(hasA2ALocalPermission(ctx))
            }
            METHOD_REQUEST_A2A_LOCAL_PERMISSION -> {
                requestA2ALocalPermission(ctx, result)
            }
            METHOD_START_A2A_LOCAL_TRANSPORT -> {
                val args = call.arguments as? Map<*, *>
                result.success(a2aLocalTransport?.start(args) ?: mapOf(
                    "supported" to false,
                    "running" to false,
                    "reason" to "transport_not_initialized"
                ))
            }
            METHOD_STOP_A2A_LOCAL_TRANSPORT -> {
                result.success(a2aLocalTransport?.stop() ?: mapOf(
                    "supported" to false,
                    "running" to false,
                    "reason" to "transport_not_initialized"
                ))
            }
            METHOD_DISCOVER_A2A_LOCAL_PEERS -> {
                val args = call.arguments as? Map<*, *>
                result.success(a2aLocalTransport?.discover(args) ?: mapOf(
                    "started" to false,
                    "reason" to "transport_not_initialized"
                ))
            }
            METHOD_SEND_A2A_LOCAL_MESSAGE -> {
                val args = call.arguments as? Map<*, *>
                result.success(a2aLocalTransport?.send(args) ?: mapOf(
                    "sent" to false,
                    "reason" to "transport_not_initialized"
                ))
            }
            METHOD_DRAIN_A2A_LOCAL_TRANSPORT_EVENTS -> {
                result.success(a2aLocalTransport?.drainEvents() ?: emptyList<Map<String, Any>>())
            }
            METHOD_GET_AGENT_PROVIDER_HOST_PACKAGE_NAME -> {
                result.success(ctx.packageName)
            }
            METHOD_GET_AGENT_PROVIDER_HOST_INFO -> {
                result.success(mapOf(
                    "packageName" to ctx.packageName,
                    "signingCertSha256" to (signingCertSha256(ctx, ctx.packageName) ?: "")
                ))
            }
            METHOD_EXECUTE_AGENT_PROVIDER_ACTION -> {
                val requestJson = call.argument<String>("requestJson") ?: ""
                executeAgentProviderAction(ctx, requestJson, result)
            }
            METHOD_SCHEDULE_AUTOMATION_WAKE -> {
                val args = call.arguments as? Map<*, *>
                result.success(NapaxiAutomationScheduler.schedule(ctx, args))
            }
            METHOD_CANCEL_AUTOMATION_WAKE -> {
                val jobId = call.argument<String>("jobId")
                result.success(NapaxiAutomationScheduler.cancel(ctx, jobId))
            }
            METHOD_GET_AUTOMATION_SCHEDULER_STATUS -> {
                result.success(NapaxiAutomationScheduler.status(ctx))
            }
            METHOD_GET_PENDING_AUTOMATION_WAKES -> {
                result.success(NapaxiAutomationScheduler.pendingWakes(ctx))
            }
            METHOD_CLEAR_PENDING_AUTOMATION_WAKE -> {
                result.success(NapaxiAutomationScheduler.clearPendingWake(ctx, call.argument<String>("wakeId")))
            }
            else -> result.notImplemented()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode == REQUEST_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionResult?.success(granted)
            pendingNotificationPermissionResult = null
            return true
        }
        if (requestCode == REQUEST_LOCATION_PERMISSION) {
            val granted = permissions.indices.any { index ->
                (permissions[index] == Manifest.permission.ACCESS_FINE_LOCATION ||
                    permissions[index] == Manifest.permission.ACCESS_COARSE_LOCATION) &&
                    grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
            }
            pendingLocationPermissionResult?.success(granted)
            pendingLocationPermissionResult = null
            return true
        }
        if (requestCode == REQUEST_A2A_LOCAL_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingA2ALocalPermissionResult?.success(granted)
            pendingA2ALocalPermissionResult = null
            return true
        }
        if (requestCode == REQUEST_MEDIA_LIBRARY_PERMISSION) {
            val pendingCall = pendingMediaLibraryPermissionCall
            val pendingResult = pendingMediaLibraryPermissionResult
            pendingMediaLibraryPermissionCall = null
            pendingMediaLibraryPermissionResult = null
            val ctx = context
            if (pendingCall != null && pendingResult != null && ctx != null) {
                val args = pendingCall.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                val types = mediaTypes(args)
                if (hasMediaLibraryPermission(ctx, types)) {
                    handleMediaLibraryCall(pendingCall, pendingResult)
                } else {
                    pendingResult.success(mediaLibraryPermissionRequired(ctx, types, requestable = true))
                }
            }
            return true
        }
        if (requestCode == REQUEST_MICROPHONE_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingMicrophonePermissionResult?.success(granted)
            pendingMicrophonePermissionResult = null
            return true
        }
        return false
    }

    override fun onNewIntent(intent: Intent): Boolean {
        captureAgentTrigger(intent)
        captureA2ADeepLink(intent)
        if (intent.action == ACTION_HOST_INSTALL_PROVIDER_AGENT ||
            intent.action == ACTION_HOST_TRIGGER_AGENT ||
            intent.action == ACTION_HOST_A2A_DEEP_LINK ||
            (intent.action == Intent.ACTION_VIEW && intent.data?.getQueryParameter("envelope") != null)) {
            activityBinding?.activity?.setIntent(intent)
            return true
        }
        return false
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_AGENT_PROVIDER_INSTALL) {
            handleAgentProviderInstallResult(resultCode, data)
            return true
        }
        if (requestCode == REQUEST_AGENT_PROVIDER_ACTION) {
            handleAgentProviderActionResult(resultCode, data)
            return true
        }
        if (requestCode != REQUEST_INSTALL_UNKNOWN_APPS) return false
        val apkPath = pendingApkInstallPath
        val pendingResult = pendingApkInstallResult
        pendingApkInstallPath = null
        pendingApkInstallResult = null

        val ctx = context
        if (ctx == null || apkPath == null || pendingResult == null) return true

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !ctx.packageManager.canRequestPackageInstalls()) {
            pendingResult.success(mapOf(
                "success" to false,
                "permissionRequired" to true,
                "error" to "Install unknown apps permission was not granted."
            ))
            return true
        }

        openPackageInstaller(ctx, apkPath, pendingResult)
        return true
    }

    private fun startService(ctx: Context, config: Map<*, *>?) {
        val notificationConfig = NapaxiNotificationManager.NotificationTextConfig.fromMap(config)
        val intent = Intent(ctx, NapaxiAgentService::class.java).apply {
            action = NapaxiAgentService.ACTION_START
            putExtra(NapaxiAgentService.EXTRA_CHANNEL_NAME, notificationConfig.channelName)
            putExtra(NapaxiAgentService.EXTRA_CHANNEL_DESCRIPTION, notificationConfig.channelDescription)
            putExtra(NapaxiAgentService.EXTRA_ONGOING_TITLE, notificationConfig.ongoingTitle)
            putExtra(NapaxiAgentService.EXTRA_ONGOING_MESSAGE, notificationConfig.ongoingMessage)
            putExtra(NapaxiAgentService.EXTRA_HITL_TITLE, notificationConfig.hitlTitle)
            putExtra(NapaxiAgentService.EXTRA_HITL_CHANNEL_SUFFIX, notificationConfig.hitlChannelSuffix)
            putExtra(NapaxiAgentService.EXTRA_HITL_CHANNEL_DESCRIPTION, notificationConfig.hitlChannelDescription)
            putExtra(NapaxiAgentService.EXTRA_COMPLETION_CHANNEL_SUFFIX, notificationConfig.completionChannelSuffix)
            putExtra(NapaxiAgentService.EXTRA_COMPLETION_CHANNEL_DESCRIPTION, notificationConfig.completionChannelDescription)
            putExtra(NapaxiAgentService.EXTRA_COMPLETION_MESSAGE, notificationConfig.completionMessage)
            putExtra(NapaxiAgentService.EXTRA_ERROR_PREFIX, notificationConfig.errorPrefix)
            putExtra(NapaxiAgentService.EXTRA_STOP_ACTION_LABEL, notificationConfig.stopActionLabel)
            putExtra(NapaxiAgentService.EXTRA_OPEN_ACTION_LABEL, notificationConfig.openActionLabel)
            putExtra(NapaxiAgentService.EXTRA_WAKELOCK_TIMEOUT_MS,
                (config?.get("wakeLockTimeoutMs") as? Int) ?: (30 * 60 * 1000))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ctx.startForegroundService(intent)
        } else {
            ctx.startService(intent)
        }
    }

    private fun requestLocationPermission(ctx: Context, result: Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || hasLocationPermission(ctx)) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        if (pendingLocationPermissionResult != null) {
            result.error("IN_PROGRESS", "Location permission request already in progress", null)
            return
        }
        pendingLocationPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ),
            REQUEST_LOCATION_PERMISSION
        )
    }

    private fun hasLocationPermission(ctx: Context): Boolean =
        ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    private fun hasA2ALocalPermission(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.NEARBY_WIFI_DEVICES) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestA2ALocalPermission(ctx: Context, result: Result) {
        if (hasA2ALocalPermission(ctx)) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        if (pendingA2ALocalPermissionResult != null) {
            result.error("IN_PROGRESS", "A2A local permission request already in progress", null)
            return
        }
        pendingA2ALocalPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES),
            REQUEST_A2A_LOCAL_PERMISSION
        )
    }

    private fun handleMediaLibraryCall(call: MethodCall, result: Result) {
        if (call.method != "mediaLibrary") {
            result.notImplemented()
            return
        }
        val ctx = context ?: run {
            result.error("UNAVAILABLE", "Context not available", null)
            return
        }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val action = (args["action"]?.toString() ?: "status").trim().lowercase(Locale.US)
        when (action) {
            "status" -> result.success(mediaLibraryStatus(ctx, mediaTypes(args)))
            "search" -> runMediaLibraryOperation(ctx, call, result, importAssets = false)
            "import" -> runMediaLibraryOperation(ctx, call, result, importAssets = true)
            else -> result.success(mapOf(
                "success" to false,
                "supported" to true,
                "action" to action,
                "error" to "Unsupported media_library action: $action"
            ))
        }
    }

    private fun runMediaLibraryOperation(
        ctx: Context,
        call: MethodCall,
        result: Result,
        importAssets: Boolean,
    ) {
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val types = mediaTypes(args)
        if (!hasMediaLibraryPermission(ctx, types)) {
            if (boolArg(args, "request_permission", "requestPermission", default = true)) {
                requestMediaLibraryPermission(ctx, call, result, types)
            } else {
                result.success(mediaLibraryPermissionRequired(ctx, types, requestable = activityBinding?.activity != null))
            }
            return
        }

        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            val response = try {
                if (importAssets) importMediaAssets(ctx, args) else searchMediaAssetsResult(ctx, args)
            } catch (e: Exception) {
                mapOf(
                    "success" to false,
                    "supported" to true,
                    "action" to (if (importAssets) "import" else "search"),
                    "error" to (e.message ?: "Media library operation failed")
                )
            }
            mainHandler.post { result.success(response) }
        }.start()
    }

    private fun requestMediaLibraryPermission(
        ctx: Context,
        call: MethodCall,
        result: Result,
        types: Set<String>,
    ) {
        val permissions = mediaLibraryPermissions(types)
            .filter { ContextCompat.checkSelfPermission(ctx, it) != PackageManager.PERMISSION_GRANTED }
            .toTypedArray()
        if (permissions.isEmpty()) {
            handleMediaLibraryCall(call, result)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(mediaLibraryPermissionRequired(ctx, types, requestable = false))
            return
        }
        if (pendingMediaLibraryPermissionResult != null) {
            result.error("IN_PROGRESS", "Media library permission request already in progress", null)
            return
        }
        pendingMediaLibraryPermissionCall = call
        pendingMediaLibraryPermissionResult = result
        ActivityCompat.requestPermissions(activity, permissions, REQUEST_MEDIA_LIBRARY_PERMISSION)
    }

    private fun mediaLibraryStatus(ctx: Context, types: Set<String>): Map<String, Any> {
        val permissions = mediaLibraryPermissions(types).toList()
        val granted = hasMediaLibraryPermission(ctx, types)
        return mapOf(
            "success" to true,
            "supported" to true,
            "action" to "status",
            "mediaTypes" to types.toList(),
            "permissionStatus" to if (granted) "authorized" else "permission_required",
            "granted" to granted,
            "permissionRequired" to !granted,
            "canRequest" to (!granted && permissions.isNotEmpty() && activityBinding?.activity != null),
            "permissions" to permissions,
            "pickAvailable" to true
        )
    }

    private fun mediaLibraryPermissionRequired(
        ctx: Context,
        types: Set<String>,
        requestable: Boolean,
    ): Map<String, Any> {
        val status = mediaLibraryStatus(ctx, types).toMutableMap()
        status["success"] = false
        status["canRequest"] = requestable
        status["error"] = "Media library permission is required."
        return status
    }

    private fun searchMediaAssetsResult(ctx: Context, args: Map<*, *>): Map<String, Any> {
        val assets = searchMediaAssets(ctx, args)
        return mapOf(
            "success" to true,
            "supported" to true,
            "action" to "search",
            "assets" to assets.map { it.toPublicMap() },
            "count" to assets.size,
            "permissionStatus" to "authorized"
        )
    }

    private fun importMediaAssets(ctx: Context, args: Map<*, *>): Map<String, Any> {
        val outputDir = args["outputDir"]?.toString().orEmpty()
        val sandboxPrefix = args["sandboxPrefix"]?.toString()?.trimEnd('/') ?: "/workspace/attachments/media"
        if (outputDir.isBlank()) {
            return mapOf(
                "success" to false,
                "supported" to true,
                "action" to "import",
                "error" to "outputDir is required"
            )
        }
        val limit = intArg(args, "limit", "max_count", "maxCount")?.coerceIn(1, 50) ?: 20
        val selected = stringListArg(args, "asset_ids", "assetIds")
        val assets = if (selected.isEmpty()) {
            searchMediaAssets(ctx, args).take(limit)
        } else {
            selected.take(limit).mapNotNull { mediaAssetForId(ctx, it) }
        }
        val dir = File(outputDir).apply { mkdirs() }
        val artifacts = mutableListOf<Map<String, Any>>()
        assets.forEachIndexed { index, asset ->
            val uri = Uri.parse(asset.contentUri)
            val filename = safeMediaFilename(asset.name, asset.mimeType, index)
            val outFile = File(dir, filename)
            ctx.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            } ?: return@forEachIndexed
            val sandboxPath = "$sandboxPrefix/$filename"
            val sizeBytes = outFile.length()
            artifacts.add(mapOf(
                "artifactId" to filename,
                "kind" to if (asset.mediaType == "image") "image" else "file",
                "mimeType" to asset.mimeType,
                "mime_type" to asset.mimeType,
                "name" to asset.name.ifBlank { filename },
                "filename" to filename,
                "uri" to sandboxPath,
                "sandbox_path" to sandboxPath,
                "sizeBytes" to sizeBytes,
                "size_bytes" to sizeBytes,
                "metadata" to asset.toMetadataMap()
            ))
        }
        return mapOf(
            "success" to true,
            "supported" to true,
            "action" to "import",
            "artifacts" to artifacts,
            "attachments" to artifacts,
            "count" to artifacts.size,
            "permissionStatus" to "authorized"
        )
    }

    private fun searchMediaAssets(ctx: Context, args: Map<*, *>): List<MediaLibraryAsset> {
        val types = mediaTypes(args)
        val limit = intArg(args, "limit", "max_count", "maxCount")?.coerceIn(1, 50) ?: 20
        val startMs = longArg(args, "start_ms", "startMs")
        val endMs = longArg(args, "end_ms", "endMs")
        return types.flatMap { type -> queryMediaAssets(ctx, type, startMs, endMs, limit) }
            .sortedByDescending { it.createdAtMs ?: 0L }
            .take(limit)
    }

    private fun queryMediaAssets(
        ctx: Context,
        mediaType: String,
        startMs: Long?,
        endMs: Long?,
        limit: Int,
    ): List<MediaLibraryAsset> {
        val isImage = mediaType == "image"
        val uri = if (isImage) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val dateTakenColumn = if (isImage) MediaStore.Images.Media.DATE_TAKEN else MediaStore.Video.Media.DATE_TAKEN
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.SIZE,
            dateTakenColumn,
        ).apply {
            if (!isImage) add(MediaStore.Video.Media.DURATION)
        }.toTypedArray()
        val assets = mutableListOf<MediaLibraryAsset>()
        ctx.contentResolver.query(uri, projection, null, null, "${MediaStore.MediaColumns.DATE_ADDED} DESC")?.use { cursor ->
            while (cursor.moveToNext() && assets.size < limit) {
                val asset = assetFromCursor(cursorColumnReader(cursor), mediaType, uri, dateTakenColumn)
                val createdAt = asset.createdAtMs
                if (createdAt != null && startMs != null && createdAt < startMs) continue
                if (createdAt != null && endMs != null && createdAt >= endMs) continue
                assets.add(asset)
            }
        }
        return assets
    }

    private fun mediaAssetForId(ctx: Context, assetId: String): MediaLibraryAsset? {
        val parts = assetId.split(":", limit = 2)
        if (parts.size != 2) return null
        val type = parts[0]
        val id = parts[1].toLongOrNull() ?: return null
        val isImage = type == "image"
        if (!isImage && type != "video") return null
        val uri = if (isImage) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val dateTakenColumn = if (isImage) MediaStore.Images.Media.DATE_TAKEN else MediaStore.Video.Media.DATE_TAKEN
        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_ADDED,
            MediaStore.MediaColumns.WIDTH,
            MediaStore.MediaColumns.HEIGHT,
            MediaStore.MediaColumns.SIZE,
            dateTakenColumn,
        ).apply {
            if (!isImage) add(MediaStore.Video.Media.DURATION)
        }.toTypedArray()
        ctx.contentResolver.query(
            uri,
            projection,
            "${MediaStore.MediaColumns._ID}=?",
            arrayOf(id.toString()),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return assetFromCursor(cursorColumnReader(cursor), type, uri, dateTakenColumn)
        }
        return null
    }

    private fun assetFromCursor(
        read: CursorColumnReader,
        mediaType: String,
        baseUri: Uri,
        dateTakenColumn: String,
    ): MediaLibraryAsset {
        val id = read.long(MediaStore.MediaColumns._ID) ?: 0L
        val dateTaken = read.long(dateTakenColumn)
        val dateAdded = read.long(MediaStore.MediaColumns.DATE_ADDED)
        val createdAtMs = when {
            dateTaken != null && dateTaken > 0L -> dateTaken
            dateAdded != null && dateAdded > 0L -> dateAdded * 1000L
            else -> null
        }
        val mimeType = read.string(MediaStore.MediaColumns.MIME_TYPE).ifBlank {
            if (mediaType == "image") "image/jpeg" else "video/mp4"
        }
        return MediaLibraryAsset(
            assetId = "$mediaType:$id",
            mediaType = mediaType,
            contentUri = ContentUris.withAppendedId(baseUri, id).toString(),
            name = read.string(MediaStore.MediaColumns.DISPLAY_NAME),
            mimeType = mimeType,
            createdAtMs = createdAtMs,
            width = read.long(MediaStore.MediaColumns.WIDTH),
            height = read.long(MediaStore.MediaColumns.HEIGHT),
            durationMs = read.long(MediaStore.Video.Media.DURATION),
            sizeBytes = read.long(MediaStore.MediaColumns.SIZE),
        )
    }

    private fun cursorColumnReader(cursor: android.database.Cursor): CursorColumnReader =
        CursorColumnReader(
            string = { column ->
                val index = cursor.getColumnIndex(column)
                if (index >= 0 && !cursor.isNull(index)) cursor.getString(index).orEmpty() else ""
            },
            long = { column ->
                val index = cursor.getColumnIndex(column)
                if (index >= 0 && !cursor.isNull(index)) cursor.getLong(index) else null
            },
        )

    private fun hasMediaLibraryPermission(ctx: Context, types: Set<String>): Boolean =
        mediaLibraryPermissions(types).all {
            ContextCompat.checkSelfPermission(ctx, it) == PackageManager.PERMISSION_GRANTED
        }

    private fun mediaLibraryPermissions(types: Set<String>): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val permissions = mutableListOf<String>()
            if (types.contains("image")) permissions.add(Manifest.permission.READ_MEDIA_IMAGES)
            if (types.contains("video")) permissions.add(Manifest.permission.READ_MEDIA_VIDEO)
            return permissions.toTypedArray()
        }
        return arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    private fun mediaTypes(args: Map<*, *>): Set<String> {
        val raw = args["media_types"] ?: args["mediaTypes"]
        val items = when (raw) {
            is List<*> -> raw.mapNotNull { it?.toString() }
            is String -> raw.split(',')
            else -> emptyList()
        }
        val types = items.map { it.trim().lowercase(Locale.US) }
            .filter { it == "image" || it == "video" }
            .toSet()
        return types.ifEmpty { setOf("image") }
    }

    private fun intArg(args: Map<*, *>, vararg keys: String): Int? =
        keys.firstNotNullOfOrNull { key ->
            when (val value = args[key]) {
                is Number -> value.toInt()
                is String -> value.trim().toIntOrNull()
                else -> null
            }
        }

    private fun longArg(args: Map<*, *>, vararg keys: String): Long? =
        keys.firstNotNullOfOrNull { key ->
            when (val value = args[key]) {
                is Number -> value.toLong()
                is String -> value.trim().toLongOrNull()
                else -> null
            }
        }

    private fun boolArg(args: Map<*, *>, snakeKey: String, camelKey: String, default: Boolean): Boolean =
        when (val value = args[snakeKey] ?: args[camelKey]) {
            is Boolean -> value
            is String -> value.equals("true", ignoreCase = true)
            else -> default
        }

    private fun stringListArg(args: Map<*, *>, vararg keys: String): List<String> =
        keys.firstNotNullOfOrNull { key ->
            when (val value = args[key]) {
                is List<*> -> value.mapNotNull { it?.toString()?.trim() }.filter { it.isNotEmpty() }
                is String -> value.split(',').map { it.trim() }.filter { it.isNotEmpty() }
                else -> null
            }
        } ?: emptyList()

    private fun safeMediaFilename(originalName: String, mimeType: String, index: Int): String {
        val ext = extensionForMedia(originalName, mimeType)
        val stem = originalName.substringBeforeLast('.', "media")
            .replace(Regex("[^A-Za-z0-9._-]+"), "_")
            .trim('_', '.', '-')
            .take(48)
            .ifBlank { "media" }
        return "${stem}_${System.currentTimeMillis()}_$index$ext"
    }

    private fun extensionForMedia(name: String, mimeType: String): String {
        val lower = name.lowercase(Locale.US)
        listOf(".jpg", ".jpeg", ".png", ".heic", ".webp", ".gif", ".mp4", ".mov").firstOrNull {
            lower.endsWith(it)
        }?.let { return it }
        return when (mimeType.lowercase(Locale.US)) {
            "image/png" -> ".png"
            "image/heic" -> ".heic"
            "image/webp" -> ".webp"
            "image/gif" -> ".gif"
            "video/quicktime" -> ".mov"
            else -> if (mimeType.startsWith("video/")) ".mp4" else ".jpg"
        }
    }

    private data class BluetoothSpeechAudioRoute(
        val audioManager: AudioManager,
        val previousMode: Int,
        val previousScoOn: Boolean,
        val previousCommunicationDevice: AudioDeviceInfo?
    )

    private fun hasMicrophonePermission(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestMicrophonePermission(ctx: Context, result: Result) {
        if (hasMicrophonePermission(ctx)) {
            result.success(true)
            return
        }
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(false)
            return
        }
        if (pendingMicrophonePermissionResult != null) {
            result.error("IN_PROGRESS", "Microphone permission request already in progress", null)
            return
        }
        pendingMicrophonePermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.RECORD_AUDIO),
            REQUEST_MICROPHONE_PERMISSION
        )
    }

    private fun hasBluetoothConnectPermission(ctx: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun captureBluetoothTranscript(ctx: Context, call: MethodCall, result: Result) {
        if (!hasMicrophonePermission(ctx)) {
            Log.w(BLUETOOTH_HEADSET_TAG, "speech capture blocked: microphone permission missing")
            result.error(
                "MICROPHONE_PERMISSION_REQUIRED",
                "Microphone permission is required before listening to a Bluetooth device.",
                null
            )
            return
        }
        if (!SpeechRecognizer.isRecognitionAvailable(ctx)) {
            Log.w(BLUETOOTH_HEADSET_TAG, "speech capture blocked: recognizer unavailable")
            result.error(
                "SPEECH_RECOGNIZER_UNAVAILABLE",
                "Android speech recognition is not available on this device.",
                null
            )
            return
        }
        if (pendingSpeechRecognitionResult != null) {
            Log.w(BLUETOOTH_HEADSET_TAG, "speech capture rejected: recognizer busy")
            result.error("SPEECH_BUSY", "Speech recognition is already running.", null)
            return
        }

        val mainHandler = Handler(Looper.getMainLooper())
        val maxDurationMs = ((call.argument<Int>("maxDurationMs") ?: 20_000)
            .coerceIn(3_000, 60_000)).toLong()
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        val deviceName = call.argument<String>("deviceName")?.trim().orEmpty()
        val recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(activityBinding?.activity ?: ctx)
        } catch (e: Exception) {
            Log.w(BLUETOOTH_HEADSET_TAG, "speech recognizer creation failed", e)
            result.error("SPEECH_RECOGNIZER_CREATE_FAILED", e.message, null)
            return
        }

        Log.i(
            BLUETOOTH_HEADSET_TAG,
            "speech capture starting deviceId=$deviceId deviceName=$deviceName timeoutMs=$maxDurationMs"
        )
        pendingSpeechRecognitionResult = result
        currentSpeechRecognizer = recognizer
        currentSpeechStartedAtMs = System.currentTimeMillis()
        currentSpeechAudioRoute = prepareBluetoothSpeechInputRoute(ctx)

        fun finishSuccess(payload: Map<String, Any?>) {
            val pending = pendingSpeechRecognitionResult ?: return
            Log.i(
                BLUETOOTH_HEADSET_TAG,
                "speech capture success durationMs=${payload["duration_ms"]} route=${payload["audio_route"]}"
            )
            cleanupSpeechRecognition()
            mainHandler.post { pending.success(payload) }
        }

        fun finishError(code: String, message: String, details: Any?) {
            val pending = pendingSpeechRecognitionResult ?: return
            Log.w(BLUETOOTH_HEADSET_TAG, "speech capture failed code=$code message=$message details=$details")
            cleanupSpeechRecognition()
            mainHandler.post { pending.error(code, message, details) }
        }

        currentSpeechTimeout = Runnable {
            finishError(
                "SPEECH_TIMEOUT",
                "No final speech transcript was received before the listening timeout.",
                mapOf("timeout_ms" to maxDurationMs)
            )
        }.also { timeout ->
            mainHandler.postDelayed(timeout, maxDurationMs)
        }

        recognizer.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}
            override fun onPartialResults(partialResults: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onError(error: Int) {
                finishError(
                    "SPEECH_RECOGNITION_FAILED",
                    speechRecognitionErrorMessage(error),
                    mapOf("code" to error)
                )
            }

            override fun onResults(results: Bundle?) {
                val transcript = results
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                    ?.trim()
                    .orEmpty()
                if (transcript.isBlank()) {
                    finishError(
                        "SPEECH_TRANSCRIPT_EMPTY",
                        "Speech recognition completed without text.",
                        null
                    )
                    return
                }
                val confidence = results
                    ?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    ?.firstOrNull()
                finishSuccess(
                    mapOf(
                        "text" to transcript,
                        "confidence" to confidence,
                        "duration_ms" to (System.currentTimeMillis() - currentSpeechStartedAtMs),
                        "platform_message_id" to "android-speech-${System.currentTimeMillis()}",
                        "device_id" to deviceId,
                        "device_name" to deviceName,
                        "audio_route" to currentSpeechAudioRouteDescription()
                    )
                )
            }
        })

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, ctx.packageName)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1_000L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1_000L)
        }
        try {
            recognizer.startListening(intent)
        } catch (e: Exception) {
            Log.w(BLUETOOTH_HEADSET_TAG, "speech capture startListening failed", e)
            finishError("SPEECH_START_FAILED", e.message ?: "Failed to start speech recognition.", null)
        }
    }

    private fun cleanupSpeechRecognition() {
        val mainHandler = Handler(Looper.getMainLooper())
        currentSpeechTimeout?.let { mainHandler.removeCallbacks(it) }
        currentSpeechTimeout = null
        try {
            currentSpeechRecognizer?.cancel()
        } catch (_: Exception) {
        }
        try {
            currentSpeechRecognizer?.destroy()
        } catch (_: Exception) {
        }
        currentSpeechRecognizer = null
        pendingSpeechRecognitionResult = null
        restoreBluetoothSpeechInputRoute()
    }

    private fun prepareBluetoothSpeechInputRoute(ctx: Context): BluetoothSpeechAudioRoute? {
        val audioManager = ctx.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
        val previousMode = audioManager.mode
        val previousScoOn = try {
            audioManager.isBluetoothScoOn
        } catch (_: Exception) {
            false
        }
        val previousCommunicationDevice =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                try {
                    audioManager.communicationDevice
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val bluetoothDevice = audioManager.availableCommunicationDevices.firstOrNull { device ->
                    device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        device.type == AudioDeviceInfo.TYPE_BLE_HEADSET ||
                        device.type == AudioDeviceInfo.TYPE_BLE_SPEAKER
                }
                if (bluetoothDevice != null) {
                    audioManager.setCommunicationDevice(bluetoothDevice)
                }
            } else {
                @Suppress("DEPRECATION")
                audioManager.startBluetoothSco()
                @Suppress("DEPRECATION")
                audioManager.isBluetoothScoOn = true
            }
        } catch (_: Exception) {
            // Speech recognition can still proceed through the system default mic.
        }
        return BluetoothSpeechAudioRoute(
            audioManager = audioManager,
            previousMode = previousMode,
            previousScoOn = previousScoOn,
            previousCommunicationDevice = previousCommunicationDevice
        )
    }

    private fun restoreBluetoothSpeechInputRoute() {
        val route = currentSpeechAudioRoute ?: return
        currentSpeechAudioRoute = null
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val previous = route.previousCommunicationDevice
                if (previous != null) {
                    route.audioManager.setCommunicationDevice(previous)
                } else {
                    route.audioManager.clearCommunicationDevice()
                }
            } else {
                if (!route.previousScoOn) {
                    @Suppress("DEPRECATION")
                    route.audioManager.stopBluetoothSco()
                }
                @Suppress("DEPRECATION")
                route.audioManager.isBluetoothScoOn = route.previousScoOn
            }
            route.audioManager.mode = route.previousMode
        } catch (_: Exception) {
        }
    }

    private fun currentSpeechAudioRouteDescription(): String {
        val route = currentSpeechAudioRoute ?: return "system_default"
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            route.audioManager.communicationDevice != null) {
            "communication_device"
        } else if (route.previousScoOn) {
            "bluetooth_sco_existing"
        } else {
            "bluetooth_sco_requested"
        }
    }

    private fun speechRecognitionErrorMessage(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_AUDIO -> "Speech recognition audio recording failed."
        SpeechRecognizer.ERROR_CLIENT -> "Speech recognition client failed."
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Microphone permission is required."
        SpeechRecognizer.ERROR_NETWORK -> "Speech recognition network failed."
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Speech recognition network timed out."
        SpeechRecognizer.ERROR_NO_MATCH -> "No speech was recognized."
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Speech recognition is busy."
        SpeechRecognizer.ERROR_SERVER -> "Speech recognition server failed."
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech was detected."
        else -> "Speech recognition failed."
    }

    private fun speakBluetoothReply(ctx: Context, call: MethodCall, result: Result) {
        val text = (call.argument<String>("spokenText")
            ?: call.argument<String>("text")
            ?: "").trim()
        if (text.isBlank()) {
            Log.i(BLUETOOTH_HEADSET_TAG, "tts skipped: empty text")
            result.success(mapOf(
                "delivered" to true,
                "receipt" to mapOf("tts_skipped" to true, "reason" to "empty_text")
            ))
            return
        }
        if (pendingTtsResult != null) {
            Log.w(BLUETOOTH_HEADSET_TAG, "tts rejected: already speaking")
            result.error("TTS_BUSY", "Text-to-speech is already speaking.", null)
            return
        }
        val appContext = ctx.applicationContext
        val utteranceId = "napaxi-tts-${System.currentTimeMillis()}"
        pendingTtsResult = result
        pendingTtsUtteranceId = utteranceId
        Log.i(
            BLUETOOTH_HEADSET_TAG,
            "tts starting utteranceId=$utteranceId chars=${text.length} deviceId=${call.argument<String>("deviceId") ?: ""}"
        )

        var engine: TextToSpeech? = null
        engine = TextToSpeech(appContext) { status ->
            val tts = engine ?: bluetoothTextToSpeech
            if (tts == null) {
                finishTtsError("TTS_UNAVAILABLE", "Text-to-speech engine was not initialized.", null)
                return@TextToSpeech
            }
            if (status != TextToSpeech.SUCCESS) {
                finishTtsError("TTS_UNAVAILABLE", "Text-to-speech engine is not available.", null)
                return@TextToSpeech
            }
            val languageResult = try {
                tts.setLanguage(Locale.getDefault())
            } catch (_: Exception) {
                TextToSpeech.LANG_NOT_SUPPORTED
            }
            if (languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED) {
                try {
                    tts.language = Locale.US
                } catch (_: Exception) {
                }
            }
            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}

                override fun onDone(doneUtteranceId: String?) {
                    if (doneUtteranceId != pendingTtsUtteranceId) return
                    finishTtsSuccess(mapOf(
                        "tts_engine" to (tts.defaultEngine ?: ""),
                        "utterance_id" to (doneUtteranceId ?: ""),
                        "device_id" to (call.argument<String>("deviceId") ?: ""),
                        "device_name" to (call.argument<String>("deviceName") ?: ""),
                        "outbound_id" to (call.argument<String>("outboundId") ?: "")
                    ))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(errorUtteranceId: String?) {
                    if (errorUtteranceId != pendingTtsUtteranceId) return
                    finishTtsError("TTS_FAILED", "Text-to-speech playback failed.", null)
                }

                override fun onError(errorUtteranceId: String?, errorCode: Int) {
                    if (errorUtteranceId != pendingTtsUtteranceId) return
                    finishTtsError(
                        "TTS_FAILED",
                        "Text-to-speech playback failed.",
                        mapOf("code" to errorCode)
                    )
                }
            })
            val params = Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            }
            val started = try {
                tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            } catch (e: Exception) {
                Log.w(BLUETOOTH_HEADSET_TAG, "tts speak failed", e)
                finishTtsError("TTS_START_FAILED", e.message ?: "Failed to start text-to-speech.", null)
                return@TextToSpeech
            }
            if (started == TextToSpeech.ERROR) {
                finishTtsError("TTS_START_FAILED", "Text-to-speech rejected the utterance.", null)
            }
        }
        bluetoothTextToSpeech = engine
    }

    private fun finishTtsSuccess(receipt: Map<String, Any>) {
        val pending = pendingTtsResult ?: return
        Log.i(BLUETOOTH_HEADSET_TAG, "tts success receipt=$receipt")
        val mainHandler = Handler(Looper.getMainLooper())
        val engine = bluetoothTextToSpeech
        bluetoothTextToSpeech = null
        pendingTtsResult = null
        pendingTtsUtteranceId = null
        try {
            engine?.setOnUtteranceProgressListener(null)
            engine?.shutdown()
        } catch (_: Exception) {
        }
        mainHandler.post {
            pending.success(mapOf("delivered" to true, "receipt" to receipt))
        }
    }

    private fun finishTtsError(code: String, message: String, details: Any?) {
        Log.w(BLUETOOTH_HEADSET_TAG, "tts failed code=$code message=$message details=$details")
        val pending = pendingTtsResult
        val mainHandler = Handler(Looper.getMainLooper())
        val engine = bluetoothTextToSpeech
        bluetoothTextToSpeech = null
        pendingTtsResult = null
        pendingTtsUtteranceId = null
        try {
            engine?.setOnUtteranceProgressListener(null)
            engine?.shutdown()
        } catch (_: Exception) {
        }
        if (pending != null) {
            mainHandler.post { pending.error(code, message, details) }
        }
    }

    private fun listBluetoothAudioDevices(
        ctx: Context,
        completion: (Map<String, Any>) -> Unit
    ) {
        if (!ctx.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)) {
            completion(mapOf(
                "supported" to false,
                "permission_granted" to false,
                "devices" to emptyList<Map<String, Any>>(),
                "other_devices" to emptyList<Map<String, Any>>(),
                "error" to "Bluetooth is not supported on this device."
            ))
            return
        }
        if (!hasBluetoothConnectPermission(ctx)) {
            completion(mapOf(
                "supported" to true,
                "permission_granted" to false,
                "devices" to emptyList<Map<String, Any>>(),
                "other_devices" to emptyList<Map<String, Any>>(),
                "error" to "Bluetooth connect permission is not granted."
            ))
            return
        }
        val adapter = bluetoothAdapter(ctx)
        if (adapter == null) {
            completion(mapOf(
                "supported" to false,
                "permission_granted" to true,
                "devices" to emptyList<Map<String, Any>>(),
                "other_devices" to emptyList<Map<String, Any>>(),
                "error" to "Bluetooth adapter is unavailable."
            ))
            return
        }
        queryConnectedBluetoothAudioProfiles(ctx, adapter) { connectedProfiles ->
            completion(buildBluetoothDeviceDiscoveryPayload(adapter, connectedProfiles))
        }
    }

    private fun queryConnectedBluetoothAudioProfiles(
        ctx: Context,
        adapter: BluetoothAdapter,
        completion: (Map<String, Set<String>>) -> Unit
    ) {
        val profiles = mutableListOf(
            BluetoothProfile.HEADSET,
            BluetoothProfile.A2DP
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            profiles.add(BluetoothProfile.HEARING_AID)
        }
        val connectedProfiles = mutableMapOf<String, MutableSet<String>>()
        val proxies = mutableListOf<Pair<Int, BluetoothProfile>>()
        val mainHandler = Handler(Looper.getMainLooper())
        var pending = profiles.size
        var completed = false

        fun finish() {
            if (completed) return
            completed = true
            for ((profile, proxy) in proxies) {
                adapter.closeProfileProxy(profile, proxy)
            }
            completion(connectedProfiles.mapValues { it.value.toSet() })
        }

        fun markDone() {
            pending -= 1
            if (pending <= 0) finish()
        }

        mainHandler.postDelayed({ finish() }, 700)

        for (profile in profiles) {
            val listener = object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(profileId: Int, proxy: BluetoothProfile) {
                    if (completed) {
                        adapter.closeProfileProxy(profileId, proxy)
                        return
                    }
                    proxies.add(profileId to proxy)
                    val profileName = bluetoothProfileName(profileId)
                    try {
                        for (device in proxy.connectedDevices) {
                            connectedProfiles
                                .getOrPut(device.address) { mutableSetOf() }
                                .add(profileName)
                        }
                    } catch (_: SecurityException) {
                        // Permission was checked before querying; if the OS revokes it
                        // mid-call, return the devices we can still classify.
                    }
                    markDone()
                }

                override fun onServiceDisconnected(profileId: Int) {
                    if (!completed) markDone()
                }
            }
            val requested = try {
                adapter.getProfileProxy(ctx, listener, profile)
            } catch (_: SecurityException) {
                false
            }
            if (!requested) markDone()
        }
    }

    private fun buildBluetoothDeviceDiscoveryPayload(
        adapter: BluetoothAdapter,
        connectedProfiles: Map<String, Set<String>>
    ): Map<String, Any> {
        return try {
            val classifiedDevices = adapter.bondedDevices
                .sortedWith(compareBy<BluetoothDevice> { it.name ?: it.address }.thenBy { it.address })
                .map { device ->
                    classifyBluetoothDevice(device, connectedProfiles[device.address] ?: emptySet())
                }
            val audioDevices = classifiedDevices.filter { device ->
                (device["recommended_channel_kinds"] as? List<*>)?.contains("bluetooth_audio") == true
            }
            val otherDevices = classifiedDevices.filterNot { device ->
                (device["recommended_channel_kinds"] as? List<*>)?.contains("bluetooth_audio") == true
            }
            mapOf(
                "supported" to true,
                "permission_granted" to true,
                "devices" to audioDevices,
                "other_devices" to otherDevices
            )
        } catch (e: SecurityException) {
            mapOf(
                "supported" to true,
                "permission_granted" to false,
                "devices" to emptyList<Map<String, Any>>(),
                "other_devices" to emptyList<Map<String, Any>>(),
                "error" to (e.message ?: "Bluetooth permission is required.")
            )
        } catch (e: Exception) {
            mapOf(
                "supported" to true,
                "permission_granted" to true,
                "devices" to emptyList<Map<String, Any>>(),
                "other_devices" to emptyList<Map<String, Any>>(),
                "error" to (e.message ?: "Failed to list Bluetooth audio devices.")
            )
        }
    }

    private fun bluetoothAdapter(ctx: Context): BluetoothAdapter? {
        val manager = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun bluetoothProfileName(profile: Int): String = when (profile) {
        BluetoothProfile.HEADSET -> "headset"
        BluetoothProfile.A2DP -> "a2dp"
        BluetoothProfile.HEARING_AID -> "hearing_aid"
        else -> "unknown"
    }

    private fun classifyBluetoothDevice(
        device: BluetoothDevice,
        connectedProfiles: Set<String>
    ): Map<String, Any> {
        val bluetoothClass = device.bluetoothClass
        val capabilities = mutableSetOf<String>()
        val profiles = connectedProfiles.toMutableSet()
        val recommendations = mutableListOf<String>()
        var kind = "unknown"
        var confidence = 0.0
        var warning: String? = null

        if ("headset" in connectedProfiles) {
            capabilities.add("audio_input")
            capabilities.add("audio_output")
            capabilities.add("push_to_talk")
        }
        if ("a2dp" in connectedProfiles || "hearing_aid" in connectedProfiles) {
            capabilities.add("audio_output")
            capabilities.add("media_control")
        }

        if (bluetoothClass == null) {
            if (connectedProfiles.isNotEmpty()) {
                kind = "unknown"
                recommendations.add("bluetooth_audio")
                confidence = 0.72
                warning = "Device type is unknown, but it is connected through an audio profile."
            } else {
                warning = "Device type is unknown. It is not shown as an audio channel by default."
            }
        } else {
            when (bluetoothClass.majorDeviceClass) {
                BluetoothClass.Device.Major.AUDIO_VIDEO -> {
                    when (bluetoothClass.deviceClass) {
                        BluetoothClass.Device.AUDIO_VIDEO_WEARABLE_HEADSET,
                        BluetoothClass.Device.AUDIO_VIDEO_HANDSFREE -> {
                            kind = "headset"
                            profiles.add("headset")
                            capabilities.add("audio_input")
                            capabilities.add("audio_output")
                            capabilities.add("push_to_talk")
                            recommendations.add("bluetooth_audio")
                            confidence = 0.92
                        }
                        BluetoothClass.Device.AUDIO_VIDEO_HEADPHONES -> {
                            kind = "headset"
                            profiles.add("a2dp")
                            capabilities.add("audio_output")
                            capabilities.add("media_control")
                            recommendations.add("bluetooth_audio")
                            confidence = 0.9
                        }
                        BluetoothClass.Device.AUDIO_VIDEO_LOUDSPEAKER,
                        BluetoothClass.Device.AUDIO_VIDEO_HIFI_AUDIO,
                        BluetoothClass.Device.AUDIO_VIDEO_PORTABLE_AUDIO -> {
                            kind = "speaker"
                            profiles.add("a2dp")
                            capabilities.add("audio_output")
                            capabilities.add("media_control")
                            recommendations.add("bluetooth_audio")
                            confidence = 0.88
                        }
                        BluetoothClass.Device.AUDIO_VIDEO_CAR_AUDIO -> {
                            kind = "car_audio"
                            profiles.add("a2dp")
                            capabilities.add("audio_output")
                            capabilities.add("media_control")
                            capabilities.add("car_context")
                            recommendations.add("bluetooth_car")
                            confidence = 0.92
                            warning = "Car audio has a different interaction model and is not attached as a headset channel."
                        }
                        else -> {
                            kind = if (connectedProfiles.isNotEmpty()) "speaker" else "unknown"
                            if (connectedProfiles.isNotEmpty()) {
                                recommendations.add("bluetooth_audio")
                                confidence = 0.7
                            } else {
                                warning = "Audio/video class is present, but the exact device type is unknown."
                                confidence = 0.45
                            }
                        }
                    }
                }
                BluetoothClass.Device.Major.PHONE -> {
                    kind = "phone"
                    recommendations.add("a2a")
                    confidence = 0.92
                    warning = "Phones should connect through Nearby/A2A instead of the Bluetooth audio channel."
                }
                BluetoothClass.Device.Major.COMPUTER -> {
                    kind = "computer"
                    recommendations.add("a2a")
                    confidence = 0.85
                }
                BluetoothClass.Device.Major.PERIPHERAL -> {
                    kind = "input"
                    profiles.add("hid")
                    recommendations.add("bluetooth_control")
                    confidence = 0.82
                }
                BluetoothClass.Device.Major.HEALTH -> {
                    kind = "sensor"
                    recommendations.add("bluetooth_sensor")
                    confidence = 0.82
                }
                BluetoothClass.Device.Major.WEARABLE -> {
                    kind = "wearable"
                    confidence = 0.75
                }
            }
        }

        return mapOf(
            "id" to device.address,
            "name" to ((device.name ?: device.address).ifBlank { device.address }),
            "bonded" to true,
            "connected" to connectedProfiles.isNotEmpty(),
            "device_kind" to kind,
            "profiles" to profiles.toList().sorted(),
            "capabilities" to capabilities.toList().sorted(),
            "recommended_channel_kinds" to recommendations.distinct(),
            "confidence" to confidence,
            "audio_input_available" to capabilities.contains("audio_input"),
            "audio_output_available" to capabilities.contains("audio_output"),
            "warning" to (warning ?: "")
        )
    }

    private fun installApk(ctx: Context, apkPath: String, result: Result) {
        if (apkPath.isBlank()) {
            result.success(mapOf(
                "success" to false,
                "error" to "apkPath is required"
            ))
            return
        }

        val apkFile = File(apkPath)
        if (!apkFile.exists() || !apkFile.isFile) {
            result.success(mapOf(
                "success" to false,
                "error" to "APK file does not exist: $apkPath"
            ))
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !ctx.packageManager.canRequestPackageInstalls()) {
            openInstallPermissionSettings(ctx, apkPath, result)
            return
        }

        openPackageInstaller(ctx, apkPath, result)
    }

    private fun openPackageInstaller(ctx: Context, apkPath: String, result: Result) {
        try {
            val apkFile = File(apkPath)
            val apkUri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.napaxi_flutter.fileprovider",
                apkFile
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(intent)
            result.success(mapOf(
                "success" to true,
                "installerOpened" to true,
                "apkPath" to apkPath
            ))
        } catch (e: Exception) {
            result.success(mapOf(
                "success" to false,
                "error" to (e.message ?: "Failed to open package installer")
            ))
        }
    }

    private fun openFile(ctx: Context, path: String, mimeType: String, result: Result) {
        if (path.isBlank()) {
            result.success(mapOf(
                "success" to false,
                "error" to "path is required"
            ))
            return
        }

        val file = File(path)
        if (!file.exists() || !file.isFile) {
            result.success(mapOf(
                "success" to false,
                "error" to "File does not exist: $path"
            ))
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.napaxi_flutter.fileprovider",
                file
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType.ifBlank { "application/octet-stream" })
                clipData = ClipData.newUri(ctx.contentResolver, file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(Intent.createChooser(intent, "Open file").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            result.success(mapOf(
                "success" to true,
                "path" to path,
                "mimeType" to mimeType
            ))
        } catch (e: Exception) {
            result.success(mapOf(
                "success" to false,
                "error" to (e.message ?: "Failed to open file")
            ))
        }
    }

    private fun listAgentProviders(ctx: Context): List<Map<String, String>> {
        val packageManager = ctx.packageManager
        val installIntent = Intent(ACTION_INSTALL_AGENT).addCategory(Intent.CATEGORY_DEFAULT)
        return packageManager.queryIntentActivities(installIntent, PackageManager.MATCH_DEFAULT_ONLY)
            .mapNotNull { info -> providerDescriptor(ctx, info) }
            .distinctBy { "${it["packageName"]}/${it["installActivityName"]}" }
    }

    private fun providerDescriptor(ctx: Context, installInfo: ResolveInfo): Map<String, String>? {
        val activityInfo = installInfo.activityInfo ?: return null
        val packageName = activityInfo.packageName ?: return null
        val installActivityName = activityInfo.name ?: return null
        val actionActivityName = findActionActivity(ctx, packageName) ?: installActivityName
        val label = runCatching {
            installInfo.loadLabel(ctx.packageManager)?.toString() ?: packageName
        }.getOrDefault(packageName)
        val digest = signingCertSha256(ctx, packageName) ?: ""
        return mapOf(
            "packageName" to packageName,
            "installActivityName" to installActivityName,
            "activityName" to actionActivityName,
            "label" to label,
            "signingCertSha256" to digest
        )
    }

    private fun findActionActivity(ctx: Context, packageName: String): String? {
        val intent = Intent(ACTION_HANDLE_PROPOSAL).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            setPackage(packageName)
        }
        return ctx.packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .firstOrNull()
            ?.activityInfo
            ?.name
    }

    private fun requestAgentProviderInstall(
        ctx: Context,
        provider: Map<String, Any>?,
        requestJson: String,
        result: Result
    ) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "An Activity is required to install an agent provider", null)
            return
        }
        if (pendingProviderInstallResult != null) {
            result.error("IN_PROGRESS", "Agent provider install already in progress", null)
            return
        }
        val packageName = provider?.stringValue("packageName") ?: ""
        val installActivityName = provider?.stringValue("installActivityName")
            ?: provider?.stringValue("activityName")
            ?: ""
        if (packageName.isBlank() || installActivityName.isBlank() || requestJson.isBlank()) {
            result.error("INVALID_ARGUMENTS", "provider package/activity and requestJson are required", null)
            return
        }
        val actionActivityName = provider?.stringValue("activityName")
            ?: findActionActivity(ctx, packageName)
            ?: installActivityName
        val digest = signingCertSha256(ctx, packageName) ?: run {
            result.error("SIGNATURE_UNAVAILABLE", "Unable to read provider signing certificate", null)
            return
        }
        pendingProviderInstallResult = result
        pendingProviderInstall = mapOf(
            "packageName" to packageName,
            "installActivityName" to installActivityName,
            "activityName" to actionActivityName,
            "signingCertSha256" to digest,
            "requestJson" to requestJson
        )
        val intent = Intent(ACTION_INSTALL_AGENT).apply {
            component = ComponentName(packageName, installActivityName)
            putExtra(EXTRA_INSTALL_REQUEST_JSON, requestJson)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_AGENT_PROVIDER_INSTALL)
        } catch (e: Exception) {
            pendingProviderInstallResult = null
            pendingProviderInstall = null
            result.error("INSTALL_HANDOFF_FAILED", e.message, null)
        }
    }

    private fun handleAgentProviderInstallResult(resultCode: Int, data: Intent?) {
        val pendingResult = pendingProviderInstallResult
        val provider = pendingProviderInstall
        pendingProviderInstallResult = null
        pendingProviderInstall = null
        if (pendingResult == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingResult.success(mapOf(
                "success" to false,
                "error" to "Provider install was canceled"
            ))
            return
        }
        val installResultJson = data.getStringExtra(EXTRA_INSTALL_RESULT_JSON)
        if (installResultJson.isNullOrBlank() || provider == null) {
            pendingResult.success(mapOf(
                "success" to false,
                "error" to "Provider install result missing"
            ))
            return
        }
        val request = runCatching { JSONObject(provider["requestJson"] ?: "{}") }.getOrNull()
        val installBinding = mapOf(
            "platform" to "android",
            "app_package_name" to (provider["packageName"] ?: ""),
            "activity_name" to (provider["activityName"] ?: ""),
            "signing_cert_sha256" to (provider["signingCertSha256"] ?: ""),
            "installed_at" to isoNow(),
            "install_request_id" to installRequestId(installResultJson),
            "protocol_version" to (request?.optInt("protocol_version", 1) ?: 1),
            "host_package_name" to (request?.optString("host_package_name") ?: ""),
            "host_signing_cert_sha256" to (request?.optString("host_signing_cert_sha256") ?: ""),
            "host_instance_id" to (request?.optString("host_instance_id") ?: ""),
            "host_shared_secret" to (request?.optString("host_shared_secret") ?: "")
        )
        pendingResult.success(mapOf(
            "success" to true,
            "installResultJson" to installResultJson,
            "installBinding" to installBinding
        ))
    }

    private fun getPendingProviderInstallRequest(): Map<String, String>? {
        val intent = activityBinding?.activity?.intent ?: return null
        if (intent.action != ACTION_HOST_INSTALL_PROVIDER_AGENT) return null
        val packageName = intent.getStringExtra("providerPackageName")
            ?: intent.getStringExtra("packageName")
            ?: intent.data?.getQueryParameter("package")
            ?: return null
        val activityName = intent.getStringExtra("activityName")
            ?: intent.data?.getQueryParameter("activity")
            ?: ""
        val installActivityName = intent.getStringExtra("installActivityName")
            ?: intent.data?.getQueryParameter("installActivity")
            ?: activityName
        return mapOf(
            "packageName" to packageName,
            "installActivityName" to installActivityName,
            "activityName" to activityName,
            "label" to packageName,
            "signingCertSha256" to ""
        )
    }

    private fun clearPendingProviderInstallRequest() {
        val activity = activityBinding?.activity ?: return
        if (activity.intent?.action == ACTION_HOST_INSTALL_PROVIDER_AGENT) {
            activity.setIntent(Intent(activity.intent).apply { action = null })
        }
    }

    private fun captureAgentTrigger(intent: Intent?) {
        if (intent?.action != ACTION_HOST_TRIGGER_AGENT) return
        val triggerJson = intent.getStringExtra(EXTRA_TRIGGER_REQUEST_JSON) ?: return
        pendingAgentTrigger = mapOf("triggerRequestJson" to triggerJson)
    }

    private fun getPendingAgentTriggerRequest(): Map<String, String>? {
        val existing = pendingAgentTrigger
        if (existing != null) return existing
        val intent = activityBinding?.activity?.intent
        captureAgentTrigger(intent)
        return pendingAgentTrigger
    }

    private fun clearPendingAgentTriggerRequest() {
        pendingAgentTrigger = null
        val activity = activityBinding?.activity ?: return
        if (activity.intent?.action == ACTION_HOST_TRIGGER_AGENT) {
            activity.setIntent(Intent(activity.intent).apply { action = null })
        }
    }

    private fun captureA2ADeepLink(intent: Intent?) {
        val sourceIntent = intent ?: return
        val envelopeJson = sourceIntent.getStringExtra(EXTRA_A2A_ENVELOPE_JSON)
            ?: sourceIntent.data?.getQueryParameter("envelope")
            ?: return
        if (sourceIntent.action != ACTION_HOST_A2A_DEEP_LINK && sourceIntent.action != Intent.ACTION_VIEW) {
            return
        }
        pendingA2ADeepLink = mapOf(
            "envelopeJson" to envelopeJson,
            "source" to (sourceIntent.data?.scheme ?: "intent")
        )
    }

    private fun getPendingA2ADeepLink(): Map<String, String>? {
        val existing = pendingA2ADeepLink
        if (existing != null) return existing
        val intent = activityBinding?.activity?.intent
        captureA2ADeepLink(intent)
        return pendingA2ADeepLink
    }

    private fun clearPendingA2ADeepLink() {
        pendingA2ADeepLink = null
        val activity = activityBinding?.activity ?: return
        val intent = activity.intent ?: return
        if (intent.action == ACTION_HOST_A2A_DEEP_LINK ||
            (intent.action == Intent.ACTION_VIEW && intent.data?.getQueryParameter("envelope") != null)) {
            activity.setIntent(Intent(intent).apply {
                action = null
                data = null
            })
        }
    }

    private fun executeAgentProviderAction(ctx: Context, requestJson: String, result: Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.success(mapOf("success" to false, "error" to "An Activity is required to execute provider actions"))
            return
        }
        if (pendingAgentActionResult != null) {
            result.success(mapOf("success" to false, "error" to "Agent provider action already in progress"))
            return
        }
        val request = runCatching { JSONObject(requestJson) }.getOrNull()
        if (request == null) {
            result.success(mapOf("success" to false, "error" to "Invalid provider action request JSON"))
            return
        }
        val proposal = request.optJSONObject("proposal") ?: JSONObject()
        val action = request.optJSONObject("action") ?: JSONObject()
        val pkg = request.optJSONObject("package") ?: JSONObject()
        val binding = pkg.optJSONObject("install_binding")
        if (binding == null) {
            result.success(mapOf("success" to false, "error" to "Provider action package is not installed with an Android binding"))
            return
        }
        val packageName = binding.optString("app_package_name")
        val activityName = binding.optString("activity_name")
        val expectedDigest = binding.optString("signing_cert_sha256")
        if (packageName.isBlank() || activityName.isBlank() || expectedDigest.isBlank()) {
            result.success(mapOf("success" to false, "error" to "Provider action binding is incomplete"))
            return
        }
        val currentDigest = signingCertSha256(ctx, packageName)
        if (currentDigest == null || !currentDigest.equals(expectedDigest, ignoreCase = true)) {
            result.success(mapOf("success" to false, "error" to "Provider app signature changed; reinstall this Agent"))
            return
        }
        pendingAgentActionResult = result
        pendingAgentActionRequestId = proposal.optString("request_id")
        val intent = Intent(ACTION_HANDLE_PROPOSAL).apply {
            component = ComponentName(packageName, activityName)
            putExtra(EXTRA_PROPOSAL_JSON, proposal.toString())
            putExtra(EXTRA_ACTION_JSON, action.toString())
            putExtra(EXTRA_PACKAGE_JSON, sanitizePackageForProvider(pkg).toString())
        }
        try {
            activity.startActivityForResult(intent, REQUEST_AGENT_PROVIDER_ACTION)
        } catch (e: Exception) {
            pendingAgentActionResult = null
            pendingAgentActionRequestId = null
            result.success(mapOf("success" to false, "error" to (e.message ?: "Provider action handoff failed")))
        }
    }

    private fun handleAgentProviderActionResult(resultCode: Int, data: Intent?) {
        val pendingResult = pendingAgentActionResult
        val requestId = pendingAgentActionRequestId
        pendingAgentActionResult = null
        pendingAgentActionRequestId = null
        if (pendingResult == null) return
        val resultJson = data?.getStringExtra(EXTRA_RESULT_JSON)
        if (resultCode == Activity.RESULT_OK && !resultJson.isNullOrBlank()) {
            pendingResult.success(mapOf("success" to true, "resultJson" to resultJson))
            return
        }
        pendingResult.success(mapOf(
            "success" to false,
            "resultJson" to failedActionResultJson(
                requestId ?: "",
                "Provider action was canceled or returned no result"
            )
        ))
    }

    private fun signingCertSha256(ctx: Context, packageName: String): String? {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ctx.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                ctx.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }
            val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.signingInfo?.apkContentsSigners
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
            val signature = signatures?.firstOrNull() ?: return null
            val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        } catch (_: Exception) {
            null
        }
    }

    private fun sanitizePackageForProvider(pkg: JSONObject): JSONObject {
        val copy = JSONObject(pkg.toString())
        val binding = copy.optJSONObject("install_binding")
        binding?.remove("host_shared_secret")
        return copy
    }

    private fun installRequestId(installResultJson: String): String =
        runCatching { JSONObject(installResultJson).optString("request_id") }.getOrDefault("")

    private fun failedActionResultJson(requestId: String, message: String): String =
        JSONObject()
            .put("request_id", requestId)
            .put("status", "failed")
            .put("result", JSONObject())
            .put("error", message)
            .put("completed_at", isoNow())
            .toString()

    private fun isoNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }

    private fun Map<String, Any>.stringValue(key: String): String? =
        this[key]?.toString()?.takeIf { it.isNotBlank() }

    private fun openInstallPermissionSettings(ctx: Context, apkPath: String, result: Result) {
        if (pendingApkInstallResult != null) {
            result.error("IN_PROGRESS", "APK install permission request already in progress", null)
            return
        }

        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${ctx.packageName}")
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }

        val activity = activityBinding?.activity
        if (activity == null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctx.startActivity(intent)
            result.success(mapOf(
                "success" to false,
                "permissionRequired" to true,
                "error" to "Install unknown apps permission is required. The Android permission screen has been opened."
            ))
            return
        }

        pendingApkInstallPath = apkPath
        pendingApkInstallResult = result
        activity.startActivityForResult(intent, REQUEST_INSTALL_UNKNOWN_APPS)
    }
}

private data class CursorColumnReader(
    val string: (String) -> String,
    val long: (String) -> Long?,
)

private data class MediaLibraryAsset(
    val assetId: String,
    val mediaType: String,
    val contentUri: String,
    val name: String,
    val mimeType: String,
    val createdAtMs: Long?,
    val width: Long?,
    val height: Long?,
    val durationMs: Long?,
    val sizeBytes: Long?,
) {
    fun toPublicMap(): Map<String, Any> = buildMap {
        put("assetId", assetId)
        put("mediaType", mediaType)
        put("mimeType", mimeType)
        put("name", name)
        createdAtMs?.let { put("createdAtMs", it) }
        width?.let { put("width", it) }
        height?.let { put("height", it) }
        durationMs?.let { put("durationMs", it) }
        sizeBytes?.let { put("sizeBytes", it) }
    }

    fun toMetadataMap(): Map<String, Any> = buildMap {
        put("source", "media_library")
        put("assetId", assetId)
        put("mediaType", mediaType)
        createdAtMs?.let { put("createdAtMs", it) }
        width?.let { put("width", it) }
        height?.let { put("height", it) }
        durationMs?.let { put("durationMs", it) }
        sizeBytes?.let { put("originalSizeBytes", it) }
    }
}
