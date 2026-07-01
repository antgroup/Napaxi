package com.napaxi.flutter

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object AgentTriggerStore {
    private const val PREFS_NAME = "agent_provider_background_triggers"
    private const val KEY_PENDING = "pending_trigger_json_queue"

    @Synchronized
    fun enqueue(context: Context, triggerJson: String) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val queue = readQueue(context).toMutableList()
        val requestId = requestId(triggerJson)
        if (requestId.isNotBlank() && queue.any { requestId(it) == requestId }) return
        queue.add(triggerJson)
        prefs.edit().putString(KEY_PENDING, JSONArray(queue).toString()).apply()
    }

    @Synchronized
    fun peek(context: Context): String? = readQueue(context).firstOrNull()

    @Synchronized
    fun remove(context: Context, triggerJson: String?) {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val queue = readQueue(context)
        if (queue.isEmpty()) return
        val requestId = requestId(triggerJson ?: "")
        val next = if (requestId.isBlank()) {
            queue.drop(1)
        } else {
            queue.filterNot { requestId(it) == requestId }
        }
        prefs.edit().putString(KEY_PENDING, JSONArray(next).toString()).apply()
    }

    private fun readQueue(context: Context): List<String> {
        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index -> array.optString(index) }
                .filter { it.isNotBlank() }
        }.getOrDefault(emptyList())
    }

    private fun requestId(triggerJson: String): String =
        runCatching { JSONObject(triggerJson).optString("request_id", "") }.getOrDefault("")
}
