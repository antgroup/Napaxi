package demo.smarthome.provider

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import org.json.JSONObject
import java.time.Instant

data class AIniceBridgeEvent(
    val eventType: String,
    val message: String,
    val payloadJson: String,
    val summary: String,
)

object AIniceEventBridge {
    private const val PREFS = "ainice_event_bridge"
    private const val MIJIA_PACKAGE = "com.xiaomi.smarthome"
    private const val LAST_SIGNATURE = "last_signature"
    private const val LAST_AT_MS = "last_at_ms"
    private const val LAST_SUMMARY = "last_summary"
    private const val LAST_RESULT = "last_result"
    private const val DEBOUNCE_MS = 90_000L

    fun isNotificationAccessEnabled(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ).orEmpty()
        val component = ComponentName(context, MijiaNotificationBridgeService::class.java)
        return enabled.split(':').any { it.equals(component.flattenToString(), ignoreCase = true) }
    }

    fun parseMijiaNotification(
        packageName: String,
        title: String,
        text: String,
        postedAtMillis: Long,
    ): AIniceBridgeEvent? {
        if (packageName != MIJIA_PACKAGE) return null
        val normalized = listOf(title, text)
            .joinToString(" ")
            .trim()
            .lowercase()
        if (normalized.isBlank()) return null
        val relevant = listOf(
            "ainice",
            "电子围栏",
            "地理围栏",
            "围栏",
            "蓝牙",
            "人体",
            "有人",
            "无人",
            "到家",
            "回家",
            "离家",
            "上线",
            "离线",
        ).any { normalized.contains(it.lowercase()) }
        if (!relevant) return null

        val eventType = when {
            normalized.contains("离家") ||
                normalized.contains("无人") ||
                normalized.contains("离线") ||
                normalized.contains("离开") -> "geofence_left"
            normalized.contains("到家") ||
                normalized.contains("回家") ||
                normalized.contains("上线") ||
                normalized.contains("有人") -> "geofence_entered"
            normalized.contains("人体") ||
                normalized.contains("移动") ||
                normalized.contains("presence") -> "presence_detected"
            else -> "mijia_geofence_event"
        }
        val message = when (eventType) {
            "geofence_entered" -> "米家电子围栏检测到有人到家，请判断是否需要打开灯光或显示欢迎点阵。"
            "geofence_left" -> "米家电子围栏检测到离家或无人状态，请判断是否需要关闭灯光或执行离家检查。"
            "presence_detected" -> "米家传感器检测到人体或移动事件，请判断是否需要调整家居状态。"
            else -> "米家电子围栏传感器产生新事件，请结合通知内容判断下一步家居动作。"
        }
        val safeTitle = title.take(120)
        val safeText = text.take(240)
        val payload = JSONObject()
            .put("sensor", "ainice_geofence")
            .put("source_package", packageName)
            .put("notification_title", safeTitle)
            .put("notification_text", safeText)
            .put("posted_at", Instant.ofEpochMilli(postedAtMillis).toString())
            .put("suggested_room", "living_room")
            .put("suggested_device", "floor_lamp")
        val summary = listOf(safeTitle, safeText)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
            .ifBlank { eventType }
        return AIniceBridgeEvent(
            eventType = eventType,
            message = message,
            payloadJson = payload.toString(),
            summary = summary,
        )
    }

    fun shouldSubmit(context: Context, event: AIniceBridgeEvent, nowMillis: Long): Boolean {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val signature = "${event.eventType}:${event.summary}"
        val lastSignature = prefs.getString(LAST_SIGNATURE, "")
        val lastAt = prefs.getLong(LAST_AT_MS, 0L)
        if (signature == lastSignature && nowMillis - lastAt < DEBOUNCE_MS) {
            return false
        }
        prefs.edit()
            .putString(LAST_SIGNATURE, signature)
            .putLong(LAST_AT_MS, nowMillis)
            .putString(LAST_SUMMARY, event.summary)
            .apply()
        return true
    }

    fun saveResult(context: Context, result: String) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(LAST_RESULT, result)
            .apply()
    }

    fun statusSummary(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val access = if (isNotificationAccessEnabled(context)) "已授权" else "未授权"
        val event = prefs.getString(LAST_SUMMARY, null)
        val result = prefs.getString(LAST_RESULT, null)
        return buildString {
            append("米家事件监听：").append(access)
            if (!event.isNullOrBlank()) append("\n最近事件：").append(event)
            if (!result.isNullOrBlank()) append("\n最近推送：").append(result)
        }
    }

    fun sampleEvent(): AIniceBridgeEvent =
        AIniceBridgeEvent(
            eventType = "geofence_entered",
            message = "米家电子围栏检测到有人到家，请判断是否需要打开灯光或显示欢迎点阵。",
            payloadJson = JSONObject()
                .put("sensor", "ainice_geofence")
                .put("source_package", MIJIA_PACKAGE)
                .put("notification_title", "AInice 电子围栏")
                .put("notification_text", "检测到 wenyu 到家")
                .put("posted_at", Instant.now().toString())
                .put("suggested_room", "living_room")
                .put("suggested_device", "floor_lamp")
                .toString(),
            summary = "AInice 电子围栏 · 检测到 wenyu 到家",
        )
}
