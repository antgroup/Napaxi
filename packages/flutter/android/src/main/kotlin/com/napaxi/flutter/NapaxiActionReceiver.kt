package com.napaxi.flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Receives notification action button clicks and forwards them to the Dart side
/// via the [NapaxiFlutterPlugin] callback.
///
/// Actions:
/// - [ACTION_STOP]: User tapped "Stop" on the ongoing notification
/// - [ACTION_APPROVE]: User approved a HITL request
/// - [ACTION_DENY]: User denied a HITL request
/// - [ACTION_VIEW]: User tapped "View" on a completion notification
class NapaxiActionReceiver : BroadcastReceiver() {

    companion object {
        private var actionCallback: ((action: String, requestId: String?, payload: String?) -> Unit)? = null

        /// Set the callback that forwards actions to the Flutter EventChannel.
        /// Called by [NapaxiFlutterPlugin.onAttachedToEngine].
        fun setActionCallback(callback: (action: String, requestId: String?, payload: String?) -> Unit) {
            actionCallback = callback
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            NapaxiNotificationManager.ACTION_STOP -> {
                actionCallback?.invoke("stop", null, null)
                // Also stop the foreground service
                NapaxiAgentService.stop(context)
            }
            NapaxiNotificationManager.ACTION_APPROVE -> {
                val requestId = intent.getStringExtra(NapaxiNotificationManager.EXTRA_REQUEST_ID)
                val payload = intent.getStringExtra(NapaxiNotificationManager.EXTRA_PAYLOAD)
                actionCallback?.invoke("hitlApprove", requestId, payload)
                // Dismiss the HITL notification after action
                NapaxiNotificationManager.cancelNotification(context, NapaxiNotificationManager.NOTIFICATION_ID_HITL)
            }
            NapaxiNotificationManager.ACTION_DENY -> {
                val requestId = intent.getStringExtra(NapaxiNotificationManager.EXTRA_REQUEST_ID)
                val payload = intent.getStringExtra(NapaxiNotificationManager.EXTRA_PAYLOAD)
                actionCallback?.invoke("hitlDeny", requestId, payload)
                NapaxiNotificationManager.cancelNotification(context, NapaxiNotificationManager.NOTIFICATION_ID_HITL)
            }
            NapaxiNotificationManager.ACTION_VIEW -> {
                val payload = intent.getStringExtra(NapaxiNotificationManager.EXTRA_PAYLOAD)
                actionCallback?.invoke("viewResult", null, payload)
                NapaxiNotificationManager.openApp(context)
            }
        }
    }
}
