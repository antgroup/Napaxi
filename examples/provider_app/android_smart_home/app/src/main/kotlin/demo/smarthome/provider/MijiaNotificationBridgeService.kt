package demo.smarthome.provider

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class MijiaNotificationBridgeService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val event = AIniceEventBridge.parseMijiaNotification(
            packageName = sbn.packageName,
            title = textExtra(sbn.notification, Notification.EXTRA_TITLE),
            text = listOf(
                textExtra(sbn.notification, Notification.EXTRA_TEXT),
                textExtra(sbn.notification, Notification.EXTRA_BIG_TEXT),
                textExtra(sbn.notification, Notification.EXTRA_SUB_TEXT),
                textExtra(sbn.notification, Notification.EXTRA_SUMMARY_TEXT),
            ).filter { it.isNotBlank() }.distinct().joinToString(" "),
            postedAtMillis = sbn.postTime,
        ) ?: return
        if (!AIniceEventBridge.shouldSubmit(this, event, System.currentTimeMillis())) return
        Thread {
            val result = SmartHomeTriggerBridge.submitBackground(this, event)
            AIniceEventBridge.saveResult(this, result.message)
        }.start()
    }

    private fun textExtra(notification: Notification, key: String): String =
        notification.extras?.getCharSequence(key)?.toString().orEmpty()
}
