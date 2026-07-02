package com.napaxi.flutter

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/// Foreground Service that keeps the Napaxi Agent running when the app is backgrounded.
///
/// This service:
/// - Shows an ongoing notification to keep the process alive
/// - Holds a partial WakeLock to prevent CPU sleep during agent execution
/// - Is NOT sticky — if killed, it won't auto-restart (agent state would be lost)
class NapaxiAgentService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var automationEngine: FlutterEngine? = null

    companion object {
        const val ACTION_START = "com.napaxi.flutter.ACTION_START"
        const val ACTION_STOP = "com.napaxi.flutter.ACTION_STOP"
        const val ACTION_AUTOMATION_WAKE = "com.napaxi.flutter.ACTION_AUTOMATION_WAKE"

        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_CHANNEL_DESCRIPTION = "channelDescription"
        const val EXTRA_ONGOING_TITLE = "ongoingTitle"
        const val EXTRA_ONGOING_MESSAGE = "ongoingMessage"
        const val EXTRA_HITL_TITLE = "hitlTitle"
        const val EXTRA_HITL_CHANNEL_SUFFIX = "hitlChannelSuffix"
        const val EXTRA_HITL_CHANNEL_DESCRIPTION = "hitlChannelDescription"
        const val EXTRA_COMPLETION_CHANNEL_SUFFIX = "completionChannelSuffix"
        const val EXTRA_COMPLETION_CHANNEL_DESCRIPTION = "completionChannelDescription"
        const val EXTRA_COMPLETION_MESSAGE = "completionMessage"
        const val EXTRA_ERROR_PREFIX = "errorPrefix"
        const val EXTRA_STOP_ACTION_LABEL = "stopActionLabel"
        const val EXTRA_OPEN_ACTION_LABEL = "openActionLabel"
        const val EXTRA_WAKELOCK_TIMEOUT_MS = "wakeLockTimeoutMs"

        const val NOTIFICATION_ID_ONGOING = 2001
        const val AUTOMATION_BACKGROUND_ENTRYPOINT = "napaxiAutomationBackgroundMain"

        private var isRunning = false

        fun isRunning(): Boolean = isRunning

        fun start(context: Context, config: Map<String, Any?>) {
            val intent = Intent(context, NapaxiAgentService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_CHANNEL_NAME, config[EXTRA_CHANNEL_NAME] as? String ?: "Agent")
                putExtra(EXTRA_CHANNEL_DESCRIPTION, config[EXTRA_CHANNEL_DESCRIPTION] as? String ?: "Napaxi Agent is running")
                putExtra(EXTRA_ONGOING_TITLE, config[EXTRA_ONGOING_TITLE] as? String ?: "Napaxi Agent")
                putExtra(EXTRA_ONGOING_MESSAGE, config[EXTRA_ONGOING_MESSAGE] as? String ?: "Agent is running...")
                putExtra(EXTRA_HITL_TITLE, config[EXTRA_HITL_TITLE] as? String ?: "Agent needs confirmation")
                putExtra(EXTRA_HITL_CHANNEL_SUFFIX, config[EXTRA_HITL_CHANNEL_SUFFIX] as? String ?: "Confirmation")
                putExtra(EXTRA_HITL_CHANNEL_DESCRIPTION, config[EXTRA_HITL_CHANNEL_DESCRIPTION] as? String ?: "Notifications requiring your confirmation")
                putExtra(EXTRA_COMPLETION_CHANNEL_SUFFIX, config[EXTRA_COMPLETION_CHANNEL_SUFFIX] as? String ?: "Completed")
                putExtra(EXTRA_COMPLETION_CHANNEL_DESCRIPTION, config[EXTRA_COMPLETION_CHANNEL_DESCRIPTION] as? String ?: "Task completion notifications")
                putExtra(EXTRA_COMPLETION_MESSAGE, config[EXTRA_COMPLETION_MESSAGE] as? String ?: "Task completed")
                putExtra(EXTRA_ERROR_PREFIX, config[EXTRA_ERROR_PREFIX] as? String ?: "Error")
                putExtra(EXTRA_STOP_ACTION_LABEL, config[EXTRA_STOP_ACTION_LABEL] as? String ?: "Stop")
                putExtra(EXTRA_OPEN_ACTION_LABEL, config[EXTRA_OPEN_ACTION_LABEL] as? String ?: "Open")
                putExtra(EXTRA_WAKELOCK_TIMEOUT_MS, config[EXTRA_WAKELOCK_TIMEOUT_MS] as? Int ?: (30 * 60 * 1000))
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, NapaxiAgentService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun startAutomationWake(context: Context) {
            val intent = Intent(context, NapaxiAgentService::class.java).apply {
                action = ACTION_AUTOMATION_WAKE
                putExtra(EXTRA_CHANNEL_NAME, "napaxi Agent")
                putExtra(EXTRA_CHANNEL_DESCRIPTION, "napaxi Agent is running")
                putExtra(EXTRA_ONGOING_TITLE, "napaxi Scheduled Task")
                putExtra(EXTRA_ONGOING_MESSAGE, "Running scheduled task...")
                putExtra(EXTRA_HITL_TITLE, "Agent needs confirmation")
                putExtra(EXTRA_HITL_CHANNEL_SUFFIX, "Confirmation")
                putExtra(EXTRA_HITL_CHANNEL_DESCRIPTION, "Notifications requiring your confirmation")
                putExtra(EXTRA_COMPLETION_CHANNEL_SUFFIX, "Completed")
                putExtra(EXTRA_COMPLETION_CHANNEL_DESCRIPTION, "Task completion notifications")
                putExtra(EXTRA_COMPLETION_MESSAGE, "Scheduled task completed")
                putExtra(EXTRA_ERROR_PREFIX, "Scheduled task failed")
                putExtra(EXTRA_STOP_ACTION_LABEL, "Stop")
                putExtra(EXTRA_OPEN_ACTION_LABEL, "Open")
                putExtra(EXTRA_WAKELOCK_TIMEOUT_MS, 30 * 60 * 1000)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock(30 * 60 * 1000L)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START, ACTION_AUTOMATION_WAKE -> {
                startForegroundFromIntent(intent)
                if (intent.action == ACTION_AUTOMATION_WAKE) {
                    startAutomationBackgroundEngine()
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        automationEngine?.destroy()
        automationEngine = null
        releaseWakeLock()
        isRunning = false
        // Only cancel the ongoing notification (ID=2001).
        // Completion/error notifications (ID=2003) should persist for the user to tap.
        NapaxiNotificationManager.cancelNotification(this, NapaxiNotificationManager.NOTIFICATION_ID_ONGOING)
        NapaxiNotificationManager.cancelNotification(this, NapaxiNotificationManager.NOTIFICATION_ID_HITL)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startForegroundFromIntent(intent: Intent) {
        val notificationConfig =
            NapaxiNotificationManager.NotificationTextConfig(
                channelName = intent.getStringExtra(EXTRA_CHANNEL_NAME) ?: "Agent",
                channelDescription =
                    intent.getStringExtra(EXTRA_CHANNEL_DESCRIPTION)
                        ?: "Napaxi Agent is running",
                ongoingTitle =
                    intent.getStringExtra(EXTRA_ONGOING_TITLE) ?: "Napaxi Agent",
                ongoingMessage =
                    intent.getStringExtra(EXTRA_ONGOING_MESSAGE)
                        ?: "Agent is running...",
                hitlTitle =
                    intent.getStringExtra(EXTRA_HITL_TITLE)
                        ?: "Agent needs confirmation",
                hitlChannelSuffix =
                    intent.getStringExtra(EXTRA_HITL_CHANNEL_SUFFIX)
                        ?: "Confirmation",
                hitlChannelDescription =
                    intent.getStringExtra(EXTRA_HITL_CHANNEL_DESCRIPTION)
                        ?: "Notifications requiring your confirmation",
                completionChannelSuffix =
                    intent.getStringExtra(EXTRA_COMPLETION_CHANNEL_SUFFIX)
                        ?: "Completed",
                completionChannelDescription =
                    intent.getStringExtra(EXTRA_COMPLETION_CHANNEL_DESCRIPTION)
                        ?: "Task completion notifications",
                completionMessage =
                    intent.getStringExtra(EXTRA_COMPLETION_MESSAGE)
                        ?: "Task completed",
                errorPrefix =
                    intent.getStringExtra(EXTRA_ERROR_PREFIX) ?: "Error",
                stopActionLabel =
                    intent.getStringExtra(EXTRA_STOP_ACTION_LABEL) ?: "Stop",
                openActionLabel =
                    intent.getStringExtra(EXTRA_OPEN_ACTION_LABEL) ?: "Open",
            )
        val wakeLockTimeoutMs = intent.getIntExtra(EXTRA_WAKELOCK_TIMEOUT_MS, 30 * 60 * 1000)

        releaseWakeLock()
        acquireWakeLock(wakeLockTimeoutMs.toLong())

        NapaxiNotificationManager.createChannels(this, notificationConfig)
        NapaxiNotificationManager.saveConfig(this, notificationConfig)
        val notification = NapaxiNotificationManager.buildOngoingNotification(
            this, notificationConfig.ongoingTitle, notificationConfig.ongoingMessage
        )
        startForeground(NOTIFICATION_ID_ONGOING, notification)
        isRunning = true
    }

    private fun startAutomationBackgroundEngine() {
        if (automationEngine != null) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val engine = FlutterEngine(applicationContext)
            registerGeneratedPlugins(engine)
            automationEngine = engine
            val entrypoint = DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                AUTOMATION_BACKGROUND_ENTRYPOINT,
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
        } catch (e: Exception) {
            NapaxiNotificationManager.showErrorNotification(
                this,
                "napaxi Scheduled Task",
                "Scheduled task failed: ${e.message ?: e.javaClass.simpleName}",
            )
            stopSelf()
        }
    }

    private fun registerGeneratedPlugins(engine: FlutterEngine) {
        runCatching {
            val clazz = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
            val method = clazz.getDeclaredMethod("registerWith", FlutterEngine::class.java)
            method.invoke(null, engine)
        }
    }

    @Suppress("DEPRECATION")
    private fun acquireWakeLock(timeoutMs: Long) {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "napaxi:agent"
        ).apply {
            acquire(timeoutMs)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
            }
        }
        wakeLock = null
    }
}
