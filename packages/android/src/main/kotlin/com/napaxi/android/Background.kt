package com.napaxi.android

import android.Manifest
import android.app.Notification
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import org.json.JSONObject

public data class BackgroundNotificationConfig(
    val channelName: String = "Agent",
    val channelDescription: String = "Napaxi Agent is running",
    val ongoingTitle: String = "Napaxi Agent",
    val ongoingMessage: String = "Agent is running...",
    val hitlTitle: String = "Agent needs confirmation",
    val hitlChannelSuffix: String = "Confirmation",
    val hitlChannelDescription: String = "Notifications requiring your confirmation",
    val completionChannelSuffix: String = "Completed",
    val completionChannelDescription: String = "Task completion notifications",
    val completionMessage: String = "Task completed",
    val errorPrefix: String = "Error",
    val stopActionLabel: String = "Stop",
    val openActionLabel: String = "Open",
) {
    public fun toMap(): Map<String, Any> = mapOf(
        "channelName" to channelName,
        "channelDescription" to channelDescription,
        "ongoingTitle" to ongoingTitle,
        "ongoingMessage" to ongoingMessage,
        "hitlTitle" to hitlTitle,
        "hitlChannelSuffix" to hitlChannelSuffix,
        "hitlChannelDescription" to hitlChannelDescription,
        "completionChannelSuffix" to completionChannelSuffix,
        "completionChannelDescription" to completionChannelDescription,
        "completionMessage" to completionMessage,
        "errorPrefix" to errorPrefix,
        "stopActionLabel" to stopActionLabel,
        "openActionLabel" to openActionLabel,
    )

    public fun toJsonObject(): JSONObject = JSONObject(toMap())
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): BackgroundNotificationConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): BackgroundNotificationConfig =
            BackgroundNotificationConfig(
                channelName = obj.optString("channelName", "Agent"),
                channelDescription = obj.optString("channelDescription", "Napaxi Agent is running"),
                ongoingTitle = obj.optString("ongoingTitle", "Napaxi Agent"),
                ongoingMessage = obj.optString("ongoingMessage", "Agent is running..."),
                hitlTitle = obj.optString("hitlTitle", "Agent needs confirmation"),
                hitlChannelSuffix = obj.optString("hitlChannelSuffix", "Confirmation"),
                hitlChannelDescription = obj.optString(
                    "hitlChannelDescription",
                    "Notifications requiring your confirmation",
                ),
                completionChannelSuffix = obj.optString("completionChannelSuffix", "Completed"),
                completionChannelDescription = obj.optString(
                    "completionChannelDescription",
                    "Task completion notifications",
                ),
                completionMessage = obj.optString("completionMessage", "Task completed"),
                errorPrefix = obj.optString("errorPrefix", "Error"),
                stopActionLabel = obj.optString("stopActionLabel", "Stop"),
                openActionLabel = obj.optString("openActionLabel", "Open"),
            )

        @JvmStatic
        public fun fromMap(map: Map<String, *>): BackgroundNotificationConfig =
            fromJsonObject(JSONObject(map))
    }
}

public typealias NotificationConfig = BackgroundNotificationConfig

public data class BackgroundConfig(
    val enabled: Boolean = true,
    val notificationConfig: BackgroundNotificationConfig = BackgroundNotificationConfig(),
    val wakeLockTimeoutMs: Int = 30 * 60 * 1000,
) {
    public val wakeLockTimeout: java.time.Duration
        get() = java.time.Duration.ofMillis(wakeLockTimeoutMs.toLong())

    public fun toMap(): Map<String, Any> =
        mapOf(
            "enabled" to enabled,
            "wakeLockTimeoutMs" to wakeLockTimeoutMs,
        ) + notificationConfig.toMap()

    public fun toJsonObject(): JSONObject = JSONObject(toMap())
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    internal fun toIntent(intent: Intent): Intent = intent
        .putExtra(NapaxiAgentService.EXTRA_CHANNEL_NAME, notificationConfig.channelName)
        .putExtra(NapaxiAgentService.EXTRA_CHANNEL_DESCRIPTION, notificationConfig.channelDescription)
        .putExtra(NapaxiAgentService.EXTRA_ONGOING_TITLE, notificationConfig.ongoingTitle)
        .putExtra(NapaxiAgentService.EXTRA_ONGOING_MESSAGE, notificationConfig.ongoingMessage)
        .putExtra(NapaxiAgentService.EXTRA_HITL_TITLE, notificationConfig.hitlTitle)
        .putExtra(NapaxiAgentService.EXTRA_HITL_CHANNEL_SUFFIX, notificationConfig.hitlChannelSuffix)
        .putExtra(NapaxiAgentService.EXTRA_HITL_CHANNEL_DESCRIPTION, notificationConfig.hitlChannelDescription)
        .putExtra(NapaxiAgentService.EXTRA_COMPLETION_CHANNEL_SUFFIX, notificationConfig.completionChannelSuffix)
        .putExtra(NapaxiAgentService.EXTRA_COMPLETION_CHANNEL_DESCRIPTION, notificationConfig.completionChannelDescription)
        .putExtra(NapaxiAgentService.EXTRA_COMPLETION_MESSAGE, notificationConfig.completionMessage)
        .putExtra(NapaxiAgentService.EXTRA_ERROR_PREFIX, notificationConfig.errorPrefix)
        .putExtra(NapaxiAgentService.EXTRA_STOP_ACTION_LABEL, notificationConfig.stopActionLabel)
        .putExtra(NapaxiAgentService.EXTRA_OPEN_ACTION_LABEL, notificationConfig.openActionLabel)
        .putExtra(NapaxiAgentService.EXTRA_WAKELOCK_TIMEOUT_MS, wakeLockTimeoutMs)

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): BackgroundConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): BackgroundConfig =
            BackgroundConfig(
                enabled = obj.optBoolean("enabled", true),
                notificationConfig = BackgroundNotificationConfig.fromJsonObject(obj),
                wakeLockTimeoutMs = obj.optInt("wakeLockTimeoutMs", 30 * 60 * 1000),
            )

        @JvmStatic
        public fun fromMap(map: Map<String, *>): BackgroundConfig =
            fromJsonObject(JSONObject(map))
    }
}

public enum class BackgroundAction(public val wireName: String) {
    Stop("stop"),
    HitlApprove("hitlApprove"),
    HitlDeny("hitlDeny"),
    ViewResult("viewResult"),
    AgentTrigger("agentTrigger"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWire(value: String?): BackgroundAction =
            entries.firstOrNull { it.wireName == value } ?: Unknown

        public fun flutterParityWireNames(): Set<String> =
            entries.map { it.wireName }.toSet()
    }
}

public data class BackgroundActionEvent(
    val action: String,
    val requestId: String = "",
    val payload: String = "",
) {
    public val actionType: BackgroundAction get() = BackgroundAction.fromWire(action)

    public fun toMap(): Map<String, String> = buildMap {
        put("action", action)
        if (requestId.isNotBlank()) put("requestId", requestId)
        if (payload.isNotBlank()) put("payload", payload)
    }

    public fun toJsonObject(): JSONObject = JSONObject(toMap())
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): BackgroundActionEvent =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): BackgroundActionEvent =
            BackgroundActionEvent(
                action = obj.optString("action"),
                requestId = obj.optString("requestId"),
                payload = obj.optString("payload"),
            )

        @JvmStatic
        public fun fromMap(map: Map<String, *>): BackgroundActionEvent =
            fromJsonObject(JSONObject(map))

        public fun fromAction(
            action: BackgroundAction,
            requestId: String? = null,
            payload: String? = null,
        ): BackgroundActionEvent =
            BackgroundActionEvent(action.wireName, requestId.orEmpty(), payload.orEmpty())

        public fun fromNotificationAction(
            action: String?,
            requestId: String? = null,
            payload: String? = null,
        ): BackgroundActionEvent? = when (action) {
            NapaxiNotificationManager.ACTION_STOP -> fromAction(BackgroundAction.Stop)
            NapaxiNotificationManager.ACTION_APPROVE -> fromAction(
                BackgroundAction.HitlApprove,
                requestId.orEmpty(),
                payload.orEmpty(),
            )
            NapaxiNotificationManager.ACTION_DENY -> fromAction(
                BackgroundAction.HitlDeny,
                requestId.orEmpty(),
                payload.orEmpty(),
            )
            NapaxiNotificationManager.ACTION_VIEW -> fromAction(
                BackgroundAction.ViewResult,
                requestId.orEmpty(),
                payload.orEmpty(),
            )
            else -> action?.let { BackgroundActionEvent(it, requestId.orEmpty(), payload.orEmpty()) }
        }
    }
}

public object NapaxiBackgroundPermissions {
    public const val REQUEST_POST_NOTIFICATIONS: Int = 4201

    public val isSupported: Boolean
        get() = true

    public fun checkNotificationPermission(context: Context): Boolean =
        if (isNotificationPermissionRequired(Build.VERSION.SDK_INT)) {
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

    public fun requestNotificationPermission(
        activity: Activity,
        requestCode: Int = REQUEST_POST_NOTIFICATIONS,
    ): Boolean {
        if (checkNotificationPermission(activity)) return true
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), requestCode)
        return false
    }

    public fun canRunInBackground(context: Context): Boolean =
        isSupported && checkNotificationPermission(context)

    public fun parseNotificationPermissionResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean? {
        if (requestCode != REQUEST_POST_NOTIFICATIONS) return null
        return permissions.indices.any { index ->
            permissions[index] == Manifest.permission.POST_NOTIFICATIONS &&
                grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
        }
    }

    public fun isNotificationPermissionRequired(sdkInt: Int): Boolean =
        sdkInt >= Build.VERSION_CODES.TIRAMISU
}

public class NapaxiBackgroundController internal constructor(
    private val context: Context,
    public var currentConfig: BackgroundConfig,
) {
    public val isRunning: Boolean get() = NapaxiAgentService.isRunning()
    public val onAction: Flow<BackgroundActionEvent> = NapaxiActionReceiver.events

    public fun updateConfig(config: BackgroundConfig) {
        currentConfig = config
    }

    public fun start() {
        val intent = currentConfig.toIntent(Intent(context, NapaxiAgentService::class.java).setAction(NapaxiAgentService.ACTION_START))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    public fun stop() {
        context.startService(Intent(context, NapaxiAgentService::class.java).setAction(NapaxiAgentService.ACTION_STOP))
    }

    public fun updateNotification(message: String, progress: Int? = null) {
        NapaxiNotificationManager.updateOngoingNotification(context, message, progress)
    }

    public fun showHitlNotification(
        requestId: String,
        question: String,
        options: List<String> = emptyList(),
    ) {
        NapaxiNotificationManager.showHitlNotification(context, requestId, question, options)
    }

    public fun showCompletionNotification(title: String = currentConfig.notificationConfig.ongoingTitle, message: String = currentConfig.notificationConfig.completionMessage) {
        NapaxiNotificationManager.showCompletionNotification(context, title, message)
    }

    public fun showErrorNotification(title: String = currentConfig.notificationConfig.ongoingTitle, message: String) {
        NapaxiNotificationManager.showErrorNotification(context, title, message)
    }

    public fun cancelNotification(notificationId: Int? = null) {
        if (notificationId == null) {
            NapaxiNotificationManager.cancelAllNotifications(context)
        } else {
            NapaxiNotificationManager.cancelNotification(context, notificationId)
        }
    }
}

public class BackgroundApi internal constructor(private val engine: NapaxiEngine) {
    public val controller: NapaxiBackgroundController?
        get() = engine.backgroundRuntime

    public val onAction: Flow<BackgroundActionEvent>
        get() = engine.backgroundRuntime?.onAction ?: NapaxiActionReceiver.events

    public fun checkNotificationPermission(context: Context): Boolean =
        NapaxiBackgroundPermissions.checkNotificationPermission(context)

    public fun requestNotificationPermission(
        activity: Activity,
        requestCode: Int = NapaxiBackgroundPermissions.REQUEST_POST_NOTIFICATIONS,
    ): Boolean =
        NapaxiBackgroundPermissions.requestNotificationPermission(activity, requestCode)

    public fun canRunInBackground(context: Context): Boolean =
        NapaxiBackgroundPermissions.canRunInBackground(context)

    public fun updateConfig(config: BackgroundConfig) {
        engine.updateBackgroundConfig(config)
    }

    public fun startService() {
        engine.startBackgroundService()
    }

    public fun stopService() {
        engine.stopBackgroundService()
    }

    public fun updateNotification(message: String, progress: Int? = null) {
        engine.backgroundRuntime?.updateNotification(message, progress)
    }

    public fun showHitlNotification(
        requestId: String,
        question: String,
        options: List<String> = emptyList(),
    ) {
        engine.backgroundRuntime?.showHitlNotification(requestId, question, options)
    }

    public fun showCompletionNotification(
        title: String = "Napaxi Agent",
        message: String = "Task completed",
    ) {
        engine.backgroundRuntime?.showCompletionNotification(title, message)
    }

    public fun showErrorNotification(
        title: String = "Napaxi Agent",
        message: String = "An error occurred",
    ) {
        engine.backgroundRuntime?.showErrorNotification(title, message)
    }

    public fun cancelNotification(notificationId: Int? = null) {
        engine.backgroundRuntime?.cancelNotification(notificationId)
    }
}

public class NapaxiAgentService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopSelf()
            ACTION_START -> {
                val timeout = intent.getIntExtra(EXTRA_WAKELOCK_TIMEOUT_MS, 30 * 60 * 1000)
                val notificationConfig = BackgroundNotificationConfig(
                    channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Agent",
                    channelDescription = intent.getStringExtra(EXTRA_CHANNEL_DESCRIPTION)
                        ?: "Napaxi Agent is running",
                    ongoingTitle = intent.getStringExtra(EXTRA_ONGOING_TITLE) ?: "Napaxi Agent",
                    ongoingMessage = intent.getStringExtra(EXTRA_ONGOING_MESSAGE)
                        ?: "Agent is running...",
                    hitlTitle = intent.getStringExtra(EXTRA_HITL_TITLE)
                        ?: "Agent needs confirmation",
                    hitlChannelSuffix = intent.getStringExtra(EXTRA_HITL_CHANNEL_SUFFIX)
                        ?: "Confirmation",
                    hitlChannelDescription = intent.getStringExtra(EXTRA_HITL_CHANNEL_DESCRIPTION)
                        ?: "Notifications requiring your confirmation",
                    completionChannelSuffix = intent.getStringExtra(EXTRA_COMPLETION_CHANNEL_SUFFIX)
                        ?: "Completed",
                    completionChannelDescription = intent.getStringExtra(EXTRA_COMPLETION_CHANNEL_DESCRIPTION)
                        ?: "Task completion notifications",
                    completionMessage = intent.getStringExtra(EXTRA_COMPLETION_MESSAGE)
                        ?: "Task completed",
                    errorPrefix = intent.getStringExtra(EXTRA_ERROR_PREFIX) ?: "Error",
                    stopActionLabel = intent.getStringExtra(EXTRA_STOP_ACTION_LABEL) ?: "Stop",
                    openActionLabel = intent.getStringExtra(EXTRA_OPEN_ACTION_LABEL) ?: "Open",
                )
                acquireWakeLock(timeout.toLong())
                NapaxiNotificationManager.createChannels(this, notificationConfig)
                NapaxiNotificationManager.saveConfig(this, notificationConfig)
                startForeground(
                    NapaxiNotificationManager.NOTIFICATION_ID_ONGOING,
                    NapaxiNotificationManager.buildOngoingNotification(
                        this,
                        notificationConfig.ongoingTitle,
                        notificationConfig.ongoingMessage,
                    ),
                )
                running = true
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        running = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock(timeoutMs: Long) {
        wakeLock?.takeIf { it.isHeld }?.release()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "napaxi:agent").apply {
            acquire(timeoutMs)
        }
    }

    public companion object {
        public const val ACTION_START = "com.napaxi.android.ACTION_START"
        public const val ACTION_STOP = "com.napaxi.android.ACTION_STOP"
        public const val EXTRA_CHANNEL_NAME = "channelName"
        public const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"
        public const val EXTRA_ONGOING_TITLE = "ongoingTitle"
        public const val EXTRA_ONGOING_MESSAGE = "ongoingMessage"
        public const val EXTRA_HITL_TITLE = "hitlTitle"
        public const val EXTRA_HITL_CHANNEL_SUFFIX = "hitlChannelSuffix"
        public const val EXTRA_HITL_CHANNEL_DESCRIPTION = "hitlChannelDescription"
        public const val EXTRA_COMPLETION_CHANNEL_SUFFIX = "completionChannelSuffix"
        public const val EXTRA_COMPLETION_CHANNEL_DESCRIPTION = "completionChannelDescription"
        public const val EXTRA_COMPLETION_MESSAGE = "completionMessage"
        public const val EXTRA_ERROR_PREFIX = "errorPrefix"
        public const val EXTRA_STOP_ACTION_LABEL = "stopActionLabel"
        public const val EXTRA_OPEN_ACTION_LABEL = "openActionLabel"
        public const val EXTRA_WAKELOCK_TIMEOUT_MS = "wakeLockTimeoutMs"
        @Volatile private var running: Boolean = false
        public fun isRunning(): Boolean = running
    }
}

public object NapaxiNotificationManager {
    public const val NOTIFICATION_ID_ONGOING = 2001
    public const val NOTIFICATION_ID_HITL = 2002
    public const val NOTIFICATION_ID_COMPLETION = 2003
    public const val ACTION_STOP = "com.napaxi.android.ACTION_AGENT_STOP"
    public const val ACTION_APPROVE = "com.napaxi.android.ACTION_HITL_APPROVE"
    public const val ACTION_DENY = "com.napaxi.android.ACTION_HITL_DENY"
    public const val ACTION_VIEW = "com.napaxi.android.ACTION_VIEW_RESULT"
    public const val EXTRA_REQUEST_ID = "requestId"
    public const val EXTRA_PAYLOAD = "payload"

    private const val CHANNEL_ONGOING = "napaxi_agent_ongoing"
    private const val CHANNEL_HITL = "napaxi_agent_hitl"
    private const val CHANNEL_COMPLETION = "napaxi_agent_completion"

    public fun ensureChannel(context: Context, name: String = "Agent", description: String = "Napaxi Agent is running") {
        createChannels(context, BackgroundNotificationConfig(channelName = name, channelDescription = description))
    }

    public fun createChannels(
        context: Context,
        config: BackgroundNotificationConfig = BackgroundNotificationConfig(),
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ONGOING,
                    config.channelName,
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = config.channelDescription
                    setShowBadge(false)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_HITL,
                    "${config.channelName} - ${config.hitlChannelSuffix}",
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    description = config.hitlChannelDescription
                    enableVibration(true)
                },
            )
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_COMPLETION,
                    "${config.channelName} - ${config.completionChannelSuffix}",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = config.completionChannelDescription
                },
            )
        }
    }

    public fun buildNotification(context: Context, title: String, message: String): Notification =
        Notification.Builder(context, CHANNEL_COMPLETION)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setOngoing(false)
            .build()

    public fun buildOngoingNotification(context: Context, title: String, message: String): Notification {
        val stopIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(context, CHANNEL_ONGOING)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(getLaunchPendingIntent(context))
            .setOngoing(true)
            .addAction(notificationAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                loadConfig(context).stopActionLabel,
                stopPendingIntent,
            ))
            .build()
    }

    public fun updateOngoingNotification(context: Context, message: String, progress: Int? = null) {
        createChannels(context, loadConfig(context))
        val config = loadConfig(context)
        val stopIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(context, CHANNEL_ONGOING)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(config.ongoingTitle)
            .setContentText(message)
            .setContentIntent(getLaunchPendingIntent(context))
            .setOngoing(true)
            .addAction(notificationAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                config.stopActionLabel,
                stopPendingIntent,
            ))
        if (progress != null) builder.setProgress(100, progress, false)
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID_ONGOING, builder.build())
    }

    public fun showHitlNotification(
        context: Context,
        requestId: String,
        question: String,
        options: List<String> = emptyList(),
    ) {
        createChannels(context, loadConfig(context))
        val config = loadConfig(context)
        val builder = Notification.Builder(context, CHANNEL_HITL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(config.hitlTitle)
            .setContentText(question)
            .setStyle(Notification.BigTextStyle().bigText(question))
            .setContentIntent(getLaunchPendingIntent(context))
            .setAutoCancel(false)
            .setOngoing(true)

        when {
            options.size >= 2 -> {
                builder.addAction(notificationAction(
                    android.R.drawable.ic_menu_save,
                    options[0],
                    hitlPendingIntent(
                        context = context,
                        requestCode = requestId.hashCode(),
                        action = ACTION_APPROVE,
                        requestId = requestId,
                        payload = options[0],
                    ),
                ))
                builder.addAction(notificationAction(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    options[1],
                    hitlPendingIntent(
                        context = context,
                        requestCode = requestId.hashCode() + 1,
                        action = ACTION_DENY,
                        requestId = requestId,
                        payload = options[1],
                    ),
                ))
            }
            options.size == 1 -> {
                builder.addAction(notificationAction(
                    android.R.drawable.ic_menu_save,
                    options[0],
                    hitlPendingIntent(
                        context = context,
                        requestCode = requestId.hashCode(),
                        action = ACTION_APPROVE,
                        requestId = requestId,
                        payload = options[0],
                    ),
                ))
            }
            else -> {
                builder.addAction(notificationAction(
                    android.R.drawable.ic_menu_view,
                    config.openActionLabel,
                    hitlPendingIntent(
                        context = context,
                        requestCode = requestId.hashCode(),
                        action = ACTION_VIEW,
                        requestId = requestId,
                    ),
                ))
            }
        }

        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIFICATION_ID_HITL, builder.build())
    }

    public fun showNotification(context: Context, id: Int, title: String, message: String) {
        createChannels(context, loadConfig(context))
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(id, buildNotification(context, title, message))
    }

    public fun showCompletionNotification(context: Context, title: String, message: String) {
        createChannels(context, loadConfig(context))
        val notification = Notification.Builder(context, CHANNEL_COMPLETION)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setContentIntent(getLaunchPendingIntent(context))
            .setAutoCancel(true)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_HITL)
        manager.notify(NOTIFICATION_ID_COMPLETION, notification)
    }

    public fun showErrorNotification(context: Context, title: String, message: String) {
        createChannels(context, loadConfig(context))
        val notification = Notification.Builder(context, CHANNEL_COMPLETION)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText("Task failed. Tap to view.")
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(getLaunchPendingIntent(context))
            .setAutoCancel(true)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_HITL)
        manager.notify(NOTIFICATION_ID_COMPLETION, notification)
    }

    public fun cancelNotification(context: Context, notificationId: Int) {
        (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(notificationId)
    }

    public fun cancelAllNotifications(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_ONGOING)
        manager.cancel(NOTIFICATION_ID_HITL)
        manager.cancel(NOTIFICATION_ID_COMPLETION)
    }

    public fun openApp(context: Context) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        context.startActivity(launchIntent)
    }

    public fun saveConfig(context: Context, config: BackgroundNotificationConfig) {
        context.getSharedPreferences("napaxi_bg", Context.MODE_PRIVATE)
            .edit()
            .putString("channelName", config.channelName)
            .putString("channelDescription", config.channelDescription)
            .putString("ongoingTitle", config.ongoingTitle)
            .putString("ongoingMessage", config.ongoingMessage)
            .putString("hitlTitle", config.hitlTitle)
            .putString("hitlChannelSuffix", config.hitlChannelSuffix)
            .putString("hitlChannelDescription", config.hitlChannelDescription)
            .putString("completionChannelSuffix", config.completionChannelSuffix)
            .putString("completionChannelDescription", config.completionChannelDescription)
            .putString("completionMessage", config.completionMessage)
            .putString("errorPrefix", config.errorPrefix)
            .putString("stopActionLabel", config.stopActionLabel)
            .putString("openActionLabel", config.openActionLabel)
            .apply()
    }

    public fun loadConfig(context: Context): BackgroundNotificationConfig {
        val prefs = context.getSharedPreferences("napaxi_bg", Context.MODE_PRIVATE)
        return BackgroundNotificationConfig(
            channelName = prefs.getString("channelName", "Agent") ?: "Agent",
            channelDescription = prefs.getString(
                "channelDescription",
                "Napaxi Agent is running",
            ) ?: "Napaxi Agent is running",
            ongoingTitle = prefs.getString("ongoingTitle", "Napaxi Agent") ?: "Napaxi Agent",
            ongoingMessage = prefs.getString("ongoingMessage", "Agent is running...")
                ?: "Agent is running...",
            hitlTitle = prefs.getString("hitlTitle", "Agent needs confirmation")
                ?: "Agent needs confirmation",
            hitlChannelSuffix = prefs.getString("hitlChannelSuffix", "Confirmation")
                ?: "Confirmation",
            hitlChannelDescription = prefs.getString(
                "hitlChannelDescription",
                "Notifications requiring your confirmation",
            ) ?: "Notifications requiring your confirmation",
            completionChannelSuffix = prefs.getString("completionChannelSuffix", "Completed")
                ?: "Completed",
            completionChannelDescription = prefs.getString(
                "completionChannelDescription",
                "Task completion notifications",
            ) ?: "Task completion notifications",
            completionMessage = prefs.getString("completionMessage", "Task completed")
                ?: "Task completed",
            errorPrefix = prefs.getString("errorPrefix", "Error") ?: "Error",
            stopActionLabel = prefs.getString("stopActionLabel", "Stop") ?: "Stop",
            openActionLabel = prefs.getString("openActionLabel", "Open") ?: "Open",
        )
    }

    private fun getLaunchPendingIntent(context: Context): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        return PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun hitlPendingIntent(
        context: Context,
        requestCode: Int,
        action: String,
        requestId: String,
        payload: String? = null,
    ): PendingIntent {
        val intent = Intent(context, NapaxiActionReceiver::class.java).apply {
            this.action = action
            putExtra(EXTRA_REQUEST_ID, requestId)
            if (payload != null) putExtra(EXTRA_PAYLOAD, payload)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationAction(
        icon: Int,
        title: String,
        intent: PendingIntent,
    ): Notification.Action = Notification.Action.Builder(
        Icon.createWithResource("android", icon),
        title,
        intent,
    ).build()
}

public class NapaxiActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val event = BackgroundActionEvent.fromNotificationAction(
            action = intent?.action,
            requestId = intent?.getStringExtra(NapaxiNotificationManager.EXTRA_REQUEST_ID),
            payload = intent?.getStringExtra(NapaxiNotificationManager.EXTRA_PAYLOAD),
        ) ?: return
        if (context != null) {
            when (event.action) {
                "stop" -> context.startService(
                    Intent(context, NapaxiAgentService::class.java).setAction(NapaxiAgentService.ACTION_STOP),
                )
                "hitlApprove", "hitlDeny" -> NapaxiNotificationManager.cancelNotification(
                    context,
                    NapaxiNotificationManager.NOTIFICATION_ID_HITL,
                )
                "viewResult" -> NapaxiNotificationManager.openApp(context)
            }
        }
        _events.tryEmit(event)
    }

    public companion object {
        private val _events = MutableSharedFlow<BackgroundActionEvent>(extraBufferCapacity = 16)
        public val events: Flow<BackgroundActionEvent> = _events.asSharedFlow()
    }
}
