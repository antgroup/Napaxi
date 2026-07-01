package com.napaxi.flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/// Manages notifications for the Napaxi Agent foreground service.
///
/// Three notification types:
/// - **Ongoing** (ID=2001): Shown while the agent is executing
/// - **HITL** (ID=2002): High-priority notification requiring user confirmation
/// - **Completion/Error** (ID=2003): Auto-cancel notification for results
object NapaxiNotificationManager {

    private const val CHANNEL_ONGOING = "napaxi_agent_ongoing"
    private const val CHANNEL_HITL = "napaxi_agent_hitl"
    private const val CHANNEL_COMPLETION = "napaxi_agent_completion"

    const val NOTIFICATION_ID_ONGOING = 2001
    const val NOTIFICATION_ID_HITL = 2002
    const val NOTIFICATION_ID_COMPLETION = 2003

    const val ACTION_STOP = "com.napaxi.flutter.ACTION_AGENT_STOP"
    const val ACTION_APPROVE = "com.napaxi.flutter.ACTION_HITL_APPROVE"
    const val ACTION_DENY = "com.napaxi.flutter.ACTION_HITL_DENY"
    const val ACTION_VIEW = "com.napaxi.flutter.ACTION_VIEW_RESULT"

    const val EXTRA_REQUEST_ID = "requestId"
    const val EXTRA_PAYLOAD = "payload"

    /// Create notification channels. Must be called before posting any notification.
    fun createChannels(context: Context, config: NotificationTextConfig) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Ongoing channel — low importance, no sound
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ONGOING,
                config.channelName,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = config.channelDescription
                setShowBadge(false)
            }
        )

        // HITL channel — high importance, with sound
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_HITL,
                "${config.channelName} - ${config.hitlChannelSuffix}",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = config.hitlChannelDescription
                enableVibration(true)
            }
        )

        // Completion channel — default importance
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_COMPLETION,
                "${config.channelName} - ${config.completionChannelSuffix}",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = config.completionChannelDescription
            }
        )
    }

    /// Get a PendingIntent that opens the app's main activity.
    private fun getLaunchIntent(context: Context): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        return PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /// Open the host app from a notification action button.
    fun openApp(context: Context) {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                setPackage(context.packageName)
            }
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
        )
        context.startActivity(launchIntent)
    }

    /// Build the ongoing notification shown while the agent is running.
    fun buildOngoingNotification(
        context: Context,
        title: String,
        message: String,
    ): Notification {
        val stopIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, CHANNEL_ONGOING)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(getLaunchIntent(context))
            .setOngoing(true)
            .setSilent(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                NotificationTextConfig.load(context).stopActionLabel,
                stopPendingIntent
            )
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    /// Update the ongoing notification with progress info.
    fun updateOngoingNotification(context: Context, message: String?, progress: Int?) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val stopIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            context, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ONGOING)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(getLaunchIntent(context))
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                NotificationTextConfig.load(context).stopActionLabel,
                stopPendingIntent
            )

        // Use shared prefs to retain title across updates
        val prefs = context.getSharedPreferences("napaxi_bg", Context.MODE_PRIVATE)
        builder.setContentTitle(prefs.getString("ongoingTitle", "Napaxi Agent"))
        builder.setContentText(message ?: prefs.getString("ongoingMessage", "Agent is running..."))

        if (progress != null) {
            builder.setProgress(100, progress, progress < 0)
        }

        manager.notify(NOTIFICATION_ID_ONGOING, builder.build())
    }

    /// Show a HITL confirmation notification with approve/deny actions.
    fun showHitlNotification(
        context: Context,
        requestId: String,
        question: String,
        options: List<String>,
    ) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val builder = NotificationCompat.Builder(context, CHANNEL_HITL)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(NotificationTextConfig.load(context).hitlTitle)
            .setContentText(question)
            .setContentIntent(getLaunchIntent(context))
            .setStyle(NotificationCompat.BigTextStyle().bigText(question))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(false)
            .setOngoing(true)

        if (options.size >= 2) {
            // Two options: approve/deny
            val approveIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
                action = ACTION_APPROVE
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_PAYLOAD, options[0])
            }
            val denyIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
                action = ACTION_DENY
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_PAYLOAD, options[1])
            }

            builder.addAction(
                android.R.drawable.ic_menu_save,
                options[0],
                PendingIntent.getBroadcast(
                    context, requestId.hashCode(), approveIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                options[1],
                PendingIntent.getBroadcast(
                    context, (requestId.hashCode() + 1), denyIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else if (options.size == 1) {
            // Single option
            val approveIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
                action = ACTION_APPROVE
                putExtra(EXTRA_REQUEST_ID, requestId)
                putExtra(EXTRA_PAYLOAD, options[0])
            }
            builder.addAction(
                android.R.drawable.ic_menu_save,
                options[0],
                PendingIntent.getBroadcast(
                    context, requestId.hashCode(), approveIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else {
            // No options — show "open app" action
            val viewIntent = Intent(context, NapaxiActionReceiver::class.java).apply {
                action = ACTION_VIEW
                putExtra(EXTRA_REQUEST_ID, requestId)
            }
            builder.addAction(
                android.R.drawable.ic_menu_view,
                NotificationTextConfig.load(context).openActionLabel,
                PendingIntent.getBroadcast(
                    context, requestId.hashCode(), viewIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }

        manager.notify(NOTIFICATION_ID_HITL, builder.build())
    }

    /// Show a task completion notification.
    fun showCompletionNotification(context: Context, title: String, message: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Tapping the notification opens the app
        val launchPendingIntent = getLaunchIntent(context)

        val notification = NotificationCompat.Builder(context, CHANNEL_COMPLETION)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .setContentIntent(launchPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        // Dismiss HITL notification if still showing
        manager.cancel(NOTIFICATION_ID_HITL)

        manager.notify(NOTIFICATION_ID_COMPLETION, notification)
    }

    /// Show an error notification.
    fun showErrorNotification(context: Context, title: String, message: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Tapping the notification opens the app
        val launchPendingIntent = getLaunchIntent(context)

        val notification = NotificationCompat.Builder(context, CHANNEL_COMPLETION)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText("Task failed. Tap to view.")
            .setStyle(NotificationCompat.BigTextStyle().bigText(message))
            .setAutoCancel(true)
            .setContentIntent(launchPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        // Dismiss HITL notification if still showing
        manager.cancel(NOTIFICATION_ID_HITL)

        manager.notify(NOTIFICATION_ID_COMPLETION, notification)
    }

    /// Cancel a specific notification by ID.
    fun cancelNotification(context: Context, notificationId: Int) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(notificationId)
    }

    /// Cancel all Napaxi notifications.
    fun cancelAllNotifications(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID_ONGOING)
        manager.cancel(NOTIFICATION_ID_HITL)
        manager.cancel(NOTIFICATION_ID_COMPLETION)
    }

    /// Save config values for notification title persistence across updates.
    fun saveConfig(context: Context, config: NotificationTextConfig) {
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
            .putString(
                "completionChannelDescription",
                config.completionChannelDescription
            )
            .putString("completionMessage", config.completionMessage)
            .putString("errorPrefix", config.errorPrefix)
            .putString("stopActionLabel", config.stopActionLabel)
            .putString("openActionLabel", config.openActionLabel)
            .apply()
    }

    data class NotificationTextConfig(
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
        companion object {
            fun fromMap(config: Map<*, *>?): NotificationTextConfig = NotificationTextConfig(
                channelName = config?.get("channelName") as? String ?: "Agent",
                channelDescription = config?.get("channelDescription") as? String
                    ?: "Napaxi Agent is running",
                ongoingTitle = config?.get("ongoingTitle") as? String ?: "Napaxi Agent",
                ongoingMessage = config?.get("ongoingMessage") as? String
                    ?: "Agent is running...",
                hitlTitle = config?.get("hitlTitle") as? String
                    ?: "Agent needs confirmation",
                hitlChannelSuffix = config?.get("hitlChannelSuffix") as? String
                    ?: "Confirmation",
                hitlChannelDescription = config?.get("hitlChannelDescription") as? String
                    ?: "Notifications requiring your confirmation",
                completionChannelSuffix = config?.get("completionChannelSuffix") as? String
                    ?: "Completed",
                completionChannelDescription =
                    config?.get("completionChannelDescription") as? String
                        ?: "Task completion notifications",
                completionMessage = config?.get("completionMessage") as? String
                    ?: "Task completed",
                errorPrefix = config?.get("errorPrefix") as? String ?: "Error",
                stopActionLabel = config?.get("stopActionLabel") as? String ?: "Stop",
                openActionLabel = config?.get("openActionLabel") as? String ?: "Open",
            )

            fun load(context: Context): NotificationTextConfig {
                val prefs = context.getSharedPreferences("napaxi_bg", Context.MODE_PRIVATE)
                return NotificationTextConfig(
                    channelName = prefs.getString("channelName", "Agent") ?: "Agent",
                    channelDescription = prefs.getString(
                        "channelDescription",
                        "Napaxi Agent is running"
                    ) ?: "Napaxi Agent is running",
                    ongoingTitle = prefs.getString("ongoingTitle", "Napaxi Agent")
                        ?: "Napaxi Agent",
                    ongoingMessage = prefs.getString("ongoingMessage", "Agent is running...")
                        ?: "Agent is running...",
                    hitlTitle = prefs.getString("hitlTitle", "Agent needs confirmation")
                        ?: "Agent needs confirmation",
                    hitlChannelSuffix = prefs.getString("hitlChannelSuffix", "Confirmation")
                        ?: "Confirmation",
                    hitlChannelDescription = prefs.getString(
                        "hitlChannelDescription",
                        "Notifications requiring your confirmation"
                    ) ?: "Notifications requiring your confirmation",
                    completionChannelSuffix = prefs.getString(
                        "completionChannelSuffix",
                        "Completed"
                    ) ?: "Completed",
                    completionChannelDescription = prefs.getString(
                        "completionChannelDescription",
                        "Task completion notifications"
                    ) ?: "Task completion notifications",
                    completionMessage = prefs.getString("completionMessage", "Task completed")
                        ?: "Task completed",
                    errorPrefix = prefs.getString("errorPrefix", "Error") ?: "Error",
                    stopActionLabel = prefs.getString("stopActionLabel", "Stop") ?: "Stop",
                    openActionLabel = prefs.getString("openActionLabel", "Open") ?: "Open",
                )
            }
        }
    }
}
