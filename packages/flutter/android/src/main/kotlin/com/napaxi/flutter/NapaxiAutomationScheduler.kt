package com.napaxi.flutter

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

object NapaxiAutomationScheduler {
    const val ACTION_WAKE = "com.napaxi.flutter.ACTION_AUTOMATION_WAKE"
    const val EXTRA_WAKE_ID = "wakeId"
    const val EXTRA_JOB_ID = "jobId"
    const val EXTRA_AT_MS = "atMs"
    const val EXTRA_TRIGGER_JSON = "triggerJson"
    const val EXTRA_SOURCE = "source"

    private const val PREFS_NAME = "napaxi_automation_scheduler"
    private const val KEY_PENDING = "pending_wakes"
    private const val KEY_NEXT = "next_wake"
    private const val REQUEST_NEXT_WAKE = 4301

    private var wakeCallback: ((Map<String, Any?>) -> Unit)? = null

    fun setWakeCallback(callback: (Map<String, Any?>) -> Unit) {
        wakeCallback = callback
    }

    fun clearWakeCallback() {
        wakeCallback = null
    }

    fun schedule(context: Context, args: Map<*, *>?): Boolean {
        val jobId = args?.get("jobId") as? String ?: return false
        val atMs = (args["atMs"] as? Number)?.toLong() ?: return false
        val triggerJson = JSONObject(args["trigger"] as? Map<*, *> ?: emptyMap<Any, Any>()).toString()
        val exact = args["exact"] as? Boolean ?: false
        if (jobId.isBlank() || atMs <= 0) return false

        val appContext = context.applicationContext
        val pendingIntent = wakePendingIntent(appContext, jobId, atMs, triggerJson)
        val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        val triggerAt = atMs.coerceAtLeast(now + 1_000)

        if (exact && canScheduleExactAlarms(alarmManager)) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }

        saveNextWake(appContext, jobId, atMs, triggerJson)
        return true
    }

    fun cancel(context: Context, jobId: String? = null): Boolean {
        val appContext = context.applicationContext
        val next = readNextWake(appContext)
        val effectiveJobId = jobId?.takeIf { it.isNotBlank() } ?: next?.optString("jobId")
        val effectiveAtMs = next?.optLong("atMs", 0L) ?: 0L
        val effectiveTriggerJson = next?.optString("triggerJson", "{}") ?: "{}"
        if (!effectiveJobId.isNullOrBlank()) {
            val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.cancel(wakePendingIntent(appContext, effectiveJobId, effectiveAtMs, effectiveTriggerJson))
        }
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_NEXT)
            .apply()
        return true
    }

    fun status(context: Context): Map<String, Any?> {
        val appContext = context.applicationContext
        val pending = pendingWakes(appContext)
        val next = readNextWake(appContext)
        return mapOf(
            "supported" to true,
            "platform" to "android",
            "pendingWakeCount" to pending.size,
            "nextPendingWake" to pending.minByOrNull { (it["firedAtMs"] as? Long) ?: Long.MAX_VALUE },
            "scheduledJobId" to next?.optString("jobId", ""),
            "scheduledAtMs" to next?.optLong("atMs", 0L),
        )
    }

    @Synchronized
    fun pendingWakes(context: Context): List<Map<String, Any?>> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val item = array.optJSONObject(index) ?: JSONObject()
                mapOf(
                    "wakeId" to item.optString("wakeId"),
                    "jobId" to item.optString("jobId"),
                    "atMs" to item.optLong("atMs", 0L),
                    "firedAtMs" to item.optLong("firedAtMs", 0L),
                    "source" to item.optString("source", "platform_wake"),
                )
            }.filter { (it["jobId"] as? String)?.isNotBlank() == true }
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun clearPendingWake(context: Context, wakeId: String?): Boolean {
        val id = wakeId?.trim() ?: ""
        val queue = pendingJsonObjects(context)
        val next = if (id.isBlank()) queue.drop(1) else queue.filterNot { it.optString("wakeId") == id }
        savePending(context, next)
        return true
    }

    @Synchronized
    fun recordWake(context: Context, intent: Intent): Map<String, Any?> {
        val appContext = context.applicationContext
        val jobId = intent.getStringExtra(EXTRA_JOB_ID) ?: ""
        val atMs = intent.getLongExtra(EXTRA_AT_MS, 0L)
        val firedAtMs = System.currentTimeMillis()
        val wakeId = intent.getStringExtra(EXTRA_WAKE_ID) ?: "$jobId:$firedAtMs"
        val entry = JSONObject()
            .put("wakeId", wakeId)
            .put("jobId", jobId)
            .put("atMs", atMs)
            .put("firedAtMs", firedAtMs)
            .put("source", intent.getStringExtra(EXTRA_SOURCE) ?: "platform_wake")
        val queue = pendingJsonObjects(appContext).filterNot { it.optString("wakeId") == wakeId }.toMutableList()
        queue.add(entry)
        savePending(appContext, queue.takeLast(50))
        appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_NEXT)
            .apply()
        val event = mapOf(
            "wakeId" to wakeId,
            "jobId" to jobId,
            "atMs" to atMs,
            "firedAtMs" to firedAtMs,
            "source" to "platform_wake",
        )
        wakeCallback?.invoke(event)
        return event
    }

    private fun wakePendingIntent(
        context: Context,
        jobId: String,
        atMs: Long,
        triggerJson: String,
    ): PendingIntent {
        val intent = Intent(context, NapaxiAutomationWakeReceiver::class.java).apply {
            action = ACTION_WAKE
            putExtra(EXTRA_WAKE_ID, "$jobId:$atMs")
            putExtra(EXTRA_JOB_ID, jobId)
            putExtra(EXTRA_AT_MS, atMs)
            putExtra(EXTRA_TRIGGER_JSON, triggerJson)
            putExtra(EXTRA_SOURCE, "platform_wake")
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_NEXT_WAKE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canScheduleExactAlarms(alarmManager: AlarmManager): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
    }

    private fun saveNextWake(context: Context, jobId: String, atMs: Long, triggerJson: String) {
        val next = JSONObject()
            .put("jobId", jobId)
            .put("atMs", atMs)
            .put("triggerJson", triggerJson)
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_NEXT, next.toString())
            .apply()
    }

    private fun readNextWake(context: Context): JSONObject? {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_NEXT, null) ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    private fun pendingJsonObjects(context: Context): List<JSONObject> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index -> array.optJSONObject(index) }
                .filterNotNull()
        }.getOrDefault(emptyList())
    }

    private fun savePending(context: Context, wakes: List<JSONObject>) {
        val array = JSONArray()
        wakes.forEach { array.put(it) }
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, array.toString())
            .apply()
    }
}
