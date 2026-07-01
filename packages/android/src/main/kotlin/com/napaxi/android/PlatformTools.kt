package com.napaxi.android

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.TimeZone
import java.util.concurrent.atomic.AtomicInteger

public class AndroidPlatformToolExecutor(
    private val context: Context,
    private val mediaToolHandler: AndroidPlatformMediaToolHandler? = null,
) {
    public fun canHandle(toolName: String): Boolean = normalizeToolName(toolName) in TOOL_NAMES

    public fun execute(
        toolName: String,
        paramsJson: String,
        contextJson: String = "{}",
        callback: McToolCallback,
    ) {
        val normalized = normalizeToolName(toolName)
        val params = runCatching { JSONObject(paramsJson.ifBlank { "{}" }) }.getOrElse {
            callback.success(failedResult(it.message ?: "Invalid tool parameters."))
            return
        }
        val toolContext = AndroidPlatformToolContext.from(context, contextJson)
        when {
            normalized == "take_photo" && mediaToolHandler != null ->
                mediaToolHandler.takePhoto(
                    AndroidPlatformMediaToolRequest(normalized, params, paramsJson, toolContext),
                    callback,
                )
            normalized == "media_library" && mediaToolHandler != null ->
                mediaToolHandler.mediaLibrary(
                    AndroidPlatformMediaToolRequest(normalized, params, paramsJson, toolContext),
                    callback,
                )
            normalized == "record_audio" && mediaToolHandler != null ->
                mediaToolHandler.recordAudio(
                    AndroidPlatformMediaToolRequest(normalized, params, paramsJson, toolContext),
                    callback,
                )
            else -> callback.success(execute(toolName, paramsJson, contextJson))
        }
    }

    public fun execute(toolName: String, paramsJson: String, contextJson: String = "{}"): String =
        runCatching {
            val params = JSONObject(paramsJson.ifBlank { "{}" })
            when (normalizeToolName(toolName)) {
                "open_url" -> openUrl(params)
                "make_call" -> makeCall(params)
                "send_sms" -> sendSms(params)
                "get_clipboard" -> getClipboard()
                "set_clipboard" -> setClipboard(params)
                "get_device_info" -> deviceInfo()
                "get_location" -> getLocation()
                "send_notification" -> sendNotification(params)
                "get_contacts" -> getContacts(params)
                "create_calendar_event" -> createCalendarEvent(params)
                "list_calendar_events" -> listCalendarEvents(params)
                "take_photo" -> unsupportedRequiresMediaHandler("take_photo")
                "media_library" -> unsupportedRequiresMediaHandler("media_library")
                "record_audio" -> unsupportedRequiresMediaHandler("record_audio")
                "set_alarm" -> setAlarm(params)
                "install_apk" -> installApk(params, contextJson)
                else -> JSONObject().put("error", "Unknown platform tool: $toolName").toString()
            }
        }.getOrElse { failedResult(it.message ?: it::class.java.simpleName) }

    private fun openUrl(params: JSONObject): String {
        val url = params.optString("url", params.optString("uri"))
        if (url.isBlank()) {
            return failedResult("Invalid URL: $url")
        }
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return JSONObject()
            .put("success", true)
            .put("ok", true)
            .put("url", url)
            .toString()
    }

    private fun makeCall(params: JSONObject): String {
        val phone = params.optString("phone_number", params.optString("phone"))
        if (phone.isBlank()) {
            return failedResult("phone_number is required")
        }
        val action = if (context.checkSelfPermission(Manifest.permission.CALL_PHONE) == PackageManager.PERMISSION_GRANTED) {
            Intent.ACTION_CALL
        } else {
            Intent.ACTION_DIAL
        }
        context.startActivity(Intent(action, Uri.parse("tel:$phone")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return JSONObject().put("success", true).put("phone_number", phone).toString()
    }

    private fun sendSms(params: JSONObject): String {
        val phone = params.optString("phone_number", params.optString("phone"))
        val body = params.optString("message", params.optString("body"))
        if (phone.isBlank()) {
            return failedResult("phone_number is required")
        }
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone"))
            .putExtra("sms_body", body)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        return JSONObject().put("success", true).put("phone_number", phone).toString()
    }

    private fun getClipboard(): String {
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = manager.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString() ?: ""
        return JSONObject()
            .put("text", text)
            .put("has_content", text.isNotEmpty())
            .toString()
    }

    private fun setClipboard(params: JSONObject): String {
        val text = params.optString("text")
        val manager = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        manager.setPrimaryClip(ClipData.newPlainText("Napaxi", text))
        return JSONObject()
            .put("success", true)
            .put("ok", true)
            .put("copied_length", text.length)
            .toString()
    }

    private fun deviceInfo(): String =
        JSONObject()
            .put("platform", "android")
            .put("brand", Build.BRAND)
            .put("android_version", Build.VERSION.RELEASE)
            .put("system_name", "Android")
            .put("system_version", Build.VERSION.RELEASE)
            .put("sdk_int", Build.VERSION.SDK_INT)
            .put("manufacturer", Build.MANUFACTURER)
            .put("model", Build.MODEL)
            .put("device", Build.DEVICE)
            .put("is_physical_device", isPhysicalDevice())
            .toString()

    private fun sendNotification(params: JSONObject): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return JSONObject().put("error", "Notification permission denied on Android.").toString()
        }
        val title = params.optString("title", "Notification")
        val message = params.optString("body", params.optString("message"))
        val id = notificationIds.incrementAndGet()
        val channel = "napaxi_platform_tools"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    channel,
                    "Napaxi Notifications",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Notifications from Napaxi AI agent"
                },
            )
        }
        val notification = android.app.Notification.Builder(context, channel)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(message)
            .setAutoCancel(true)
            .build()
        manager.notify(id, notification)
        return JSONObject().put("success", true).put("notification_id", id).toString()
    }

    private fun getContacts(params: JSONObject): String {
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            return JSONObject().put("error", "Contacts permission denied by user.").toString()
        }
        val query = params.optString("query").trim()
        val limit = params.optInt("limit", 20).coerceAtMost(100)
        val contacts = JSONArray()
        context.contentResolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY),
            null,
            null,
            ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
        )?.use { cursor ->
            while (cursor.moveToNext() && contacts.length() < limit) {
                val id = cursor.getString(0)
                val name = cursor.getString(1).orEmpty()
                if (query.isNotEmpty() && !name.contains(query, ignoreCase = true)) continue
                contacts.put(
                    JSONObject()
                        .put("id", id)
                        .put("display_name", name)
                        .put("name", name)
                        .put("phones", contactPhones(id))
                        .put("emails", contactEmails(id)),
                )
            }
        }
        return JSONObject().put("contacts", contacts).put("total", contacts.length()).toString()
    }

    private fun createCalendarEvent(params: JSONObject): String {
        val permError = calendarPermissionError(write = true)
        if (permError != null) return permError
        val title = params.optString("title")
        require(title.isNotBlank()) { "title is required" }
        val start = parseInstantMillis(params.optString("start"))
            ?: return JSONObject().put("error", "Invalid date format. Use ISO 8601.").toString()
        val end = parseInstantMillis(params.optString("end"))
            ?: return JSONObject().put("error", "Invalid date format. Use ISO 8601.").toString()
        val calendarId = defaultCalendarId()
            ?: return JSONObject().put("error", "No calendar found on device.").toString()

        val uri = context.contentResolver.insert(
            CalendarContract.Events.CONTENT_URI,
            ContentValues().apply {
                put(CalendarContract.Events.CALENDAR_ID, calendarId)
                put(CalendarContract.Events.TITLE, title)
                put(CalendarContract.Events.DESCRIPTION, params.optString("description"))
                put(CalendarContract.Events.DTSTART, start)
                put(CalendarContract.Events.DTEND, end)
                put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            },
        ) ?: return JSONObject().put("error", "Failed to create event: insert returned null").toString()

        return JSONObject()
            .put("success", true)
            .put("event_id", uri.lastPathSegment.orEmpty())
            .put("title", title)
            .put("start", params.optString("start"))
            .put("end", params.optString("end"))
            .toString()
    }

    private fun listCalendarEvents(params: JSONObject): String {
        val permError = calendarPermissionError(write = false)
        if (permError != null) return permError
        val start = parseInstantMillis(params.optString("start"))
            ?: return JSONObject().put("error", "Invalid date format. Use ISO 8601.").toString()
        val end = parseInstantMillis(params.optString("end"))
            ?: return JSONObject().put("error", "Invalid date format. Use ISO 8601.").toString()
        val events = JSONArray()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(start.toString())
            .appendPath(end.toString())
            .build()
        context.contentResolver.query(
            uri,
            arrayOf(
                CalendarContract.Instances.TITLE,
                CalendarContract.Instances.BEGIN,
                CalendarContract.Instances.END,
                CalendarContract.Instances.DESCRIPTION,
                CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
                CalendarContract.Instances.ALL_DAY,
            ),
            null,
            null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                events.put(
                    JSONObject()
                        .put("title", cursor.getString(0).orEmpty())
                        .put("start", millisToIso(cursor.getLong(1)))
                        .put("end", millisToIso(cursor.getLong(2)))
                        .put("description", cursor.getString(3).orEmpty())
                        .put("calendar", cursor.getString(4).orEmpty())
                        .put("all_day", cursor.getInt(5) != 0),
                )
            }
        }
        return JSONObject().put("events", events).put("count", events.length()).toString()
    }

    private fun setAlarm(params: JSONObject): String {
        val alarm = runCatching { parseAlarm(params) }.getOrElse {
            return JSONObject().put("error", it.message ?: "Invalid alarm parameters.").toString()
        }
        val intent = Intent(android.provider.AlarmClock.ACTION_SET_ALARM)
            .putExtra(android.provider.AlarmClock.EXTRA_HOUR, alarm.hour)
            .putExtra(android.provider.AlarmClock.EXTRA_MINUTES, alarm.minute)
            .putExtra(android.provider.AlarmClock.EXTRA_MESSAGE, alarm.message)
            .putExtra(android.provider.AlarmClock.EXTRA_SKIP_UI, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (alarm.repeatDays.isNotEmpty()) {
            intent.putExtra(android.provider.AlarmClock.EXTRA_DAYS, alarm.repeatDays.toIntArray())
        }
        context.startActivity(intent)
        return JSONObject()
            .put("success", true)
            .put("hour", alarm.hour)
            .put("minute", alarm.minute)
            .put("message", alarm.message)
            .also { if (alarm.repeatDays.isNotEmpty()) it.put("repeat_days", JSONArray(alarm.repeatDays)) }
            .toString()
    }

    private fun installApk(params: JSONObject, contextJson: String): String {
        val rawPath = params.optString("apk_path", params.optString("apkPath", params.optString("path")))
        if (rawPath.isBlank()) {
            return JSONObject()
                .put("success", false)
                .put("installerOpened", false)
                .put("permissionRequired", false)
                .put("error", "apk_path is required.")
                .put("code", "missing_apk_path")
                .toString()
        }
        val resolvedPath = AndroidPlatformToolContext.from(context, contextJson).resolveSandboxOrLocalPath(rawPath)
        val apk = File(resolvedPath)
        if (!apk.exists() || !apk.isFile) {
            return JSONObject()
                .put("success", false)
                .put("installerOpened", false)
                .put("permissionRequired", false)
                .put("apkPath", resolvedPath)
                .put("error", "APK file does not exist: $rawPath")
                .put("code", "apk_not_found")
                .apply {
                    if (resolvedPath != rawPath) put("resolved_path", resolvedPath)
                }
                .toString()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return JSONObject()
                .put("success", false)
                .put("installerOpened", false)
                .put("permissionRequired", true)
                .put("apkPath", resolvedPath)
                .put(
                    "error",
                    "Install unknown apps permission is required. The Android permission screen has been opened.",
                )
                .put("code", "REQUEST_INSTALL_PACKAGES")
                .toString()
        }
        val uri = NapaxiFileProvider.uriForFile(context, apk)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        return JSONObject()
            .put("success", true)
            .put("installerOpened", true)
            .put("permissionRequired", false)
            .put("apkPath", resolvedPath)
            .toString()
    }

    private fun getLocation(): String {
        if (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED
        ) {
            return JSONObject().put("error", "Location permission denied by user.").toString()
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            .filter { provider -> runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false) }
        if (providers.isEmpty()) {
            return JSONObject()
                .put("error", "Location services are disabled. Please enable them in Settings.")
                .toString()
        }
        val location = providers
            .mapNotNull { provider -> runCatching { manager.getLastKnownLocation(provider) }.getOrNull() }
            .maxByOrNull(Location::getTime)
            ?: return JSONObject().put("error", "Location unavailable.").toString()

        return JSONObject()
            .put("latitude", location.latitude)
            .put("longitude", location.longitude)
            .put("altitude", location.altitude)
            .put("accuracy", location.accuracy.toDouble())
            .put("speed", location.speed.toDouble())
            .put("timestamp", millisToIso(location.time))
            .toString()
    }

    private fun contactPhones(contactId: String): JSONArray {
        val phones = JSONArray()
        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
            "${ContactsContract.CommonDataKinds.Phone.CONTACT_ID}=?",
            arrayOf(contactId),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) phones.put(cursor.getString(0).orEmpty())
        }
        return phones
    }

    private fun contactEmails(contactId: String): JSONArray {
        val emails = JSONArray()
        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Email.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Email.ADDRESS),
            "${ContactsContract.CommonDataKinds.Email.CONTACT_ID}=?",
            arrayOf(contactId),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) emails.put(cursor.getString(0).orEmpty())
        }
        return emails
    }

    private fun calendarPermissionError(write: Boolean): String? {
        val readGranted = context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        val writeGranted = context.checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
        return if (!readGranted || (write && !writeGranted)) {
            JSONObject().put("error", "Calendar permission denied by user.").toString()
        } else {
            null
        }
    }

    private fun defaultCalendarId(): Long? {
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID, CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL),
            null,
            null,
            "${CalendarContract.Calendars.IS_PRIMARY} DESC",
        )?.use { cursor ->
            var fallback: Long? = null
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val access = cursor.getInt(1)
                if (fallback == null) fallback = id
                if (access >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR) return id
            }
            return fallback
        }
        return null
    }

    private fun permissionStatus(name: String, vararg permissions: String): String =
        JSONObject()
            .put("status", "permission_required")
            .put("capability", name)
            .put(
                "granted",
                permissions.any { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED },
            )
            .toString()

    private fun unsupportedRequiresMediaHandler(name: String): String =
        JSONObject()
            .put("error", "$name requires an AndroidPlatformMediaToolHandler")
            .put("success", false)
            .toString()

    private fun failedResult(message: String): String =
        JSONObject()
            .put("success", false)
            .put("error", message)
            .toString()

    private fun isPhysicalDevice(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val product = Build.PRODUCT.lowercase()
        return listOf(fingerprint, model, brand, device, product).none { value ->
            value.contains("generic") ||
                value.contains("emulator") ||
                value.contains("sdk_gphone") ||
                value.contains("ranchu")
        }
    }

    public companion object {
        public val isSupported: Boolean = true
        private val notificationIds = AtomicInteger(3000)
        private val TOOL_NAMES = setOf(
            "open_url",
            "make_call",
            "send_sms",
            "get_clipboard",
            "set_clipboard",
            "get_device_info",
            "get_location",
            "send_notification",
            "get_contacts",
            "create_calendar_event",
            "list_calendar_events",
            "take_photo",
            "media_library",
            "record_audio",
            "set_alarm",
            "install_apk",
        )
        public val platformToolNames: Set<String> = TOOL_NAMES

        public fun normalizeToolName(toolName: String): String =
            toolName.removePrefix("napaxi.platform_tool.")

        public fun parseAlarm(params: JSONObject): AlarmSpec {
            val time = params.optString("time")
            val (hour, minute) = if (time.isNotBlank()) {
                parseAlarmTime(time)
            } else {
                params.optInt("hour", -1) to params.optInt("minute", 0)
            }
            require(hour in 0..23 && minute in 0..59) {
                "Invalid alarm time. Hour must be 0-23 and minute must be 0-59."
            }
            return AlarmSpec(
                hour = hour,
                minute = minute,
                message = params.optString("message", "Alarm"),
                repeatDays = parseRepeatDays(
                    when {
                        params.has("repeat_days") -> params.get("repeat_days")
                        params.has("repeatDays") -> params.get("repeatDays")
                        params.has("days") -> params.get("days")
                        else -> null
                    },
                ),
            )
        }

        private fun parseAlarmTime(time: String): Pair<Int, Int> {
            val hhmm = Regex("""^(\d{1,2}):(\d{2})$""").matchEntire(time)
            if (hhmm != null) {
                return hhmm.groupValues[1].toInt() to hhmm.groupValues[2].toInt()
            }
            val instant = parseInstantMillis(time)
            require(instant != null) {
                "Invalid time format. Use HH:mm (e.g. \"07:30\") or ISO 8601."
            }
            val calendar = java.util.Calendar.getInstance().apply {
                timeInMillis = instant
            }
            return calendar.get(java.util.Calendar.HOUR_OF_DAY) to calendar.get(java.util.Calendar.MINUTE)
        }

        private fun parseRepeatDays(rawDays: Any?): List<Int> {
            if (rawDays == null || rawDays == JSONObject.NULL) return emptyList()
            val days = mutableListOf<Int>()
            val seen = mutableSetOf<Int>()

            fun add(day: Int) {
                require(day in 1..7) { "Invalid repeat day: $day." }
                if (seen.add(day)) days.add(day)
            }

            fun parseOne(raw: Any?) {
                when (raw) {
                    null, JSONObject.NULL -> return
                    is Number -> add(raw.toInt())
                    is String -> {
                        val normalized = raw.trim().lowercase()
                        if (normalized.isBlank()) return
                        REPEAT_DAY_PRESETS[normalized]?.forEach(::add) ?: run {
                            if (normalized.contains(",")) {
                                normalized.split(",").forEach(::parseOne)
                            } else {
                                add(REPEAT_DAY_ALIASES[normalized] ?: error("Invalid repeat day: $raw."))
                            }
                        }
                    }
                    else -> error("Invalid repeat day: $raw.")
                }
            }

            if (rawDays is JSONArray) {
                for (index in 0 until rawDays.length()) parseOne(rawDays.get(index))
            } else {
                parseOne(rawDays)
            }
            return days
        }
    }
}

public interface AndroidPlatformMediaToolHandler {
    public fun takePhoto(request: AndroidPlatformMediaToolRequest, callback: McToolCallback)

    public fun mediaLibrary(request: AndroidPlatformMediaToolRequest, callback: McToolCallback) {
        callback.success(
            JSONObject()
                .put("success", false)
                .put("error", "media_library requires host media library implementation")
                .toString(),
        )
    }

    public fun recordAudio(request: AndroidPlatformMediaToolRequest, callback: McToolCallback)
}

public data class AndroidPlatformMediaToolRequest(
    val toolName: String,
    val params: JSONObject,
    val paramsJson: String,
    val context: AndroidPlatformToolContext,
) {
    public val durationSeconds: Int
        get() = params.optInt("duration_seconds", params.optInt("durationSecs", 10)).coerceIn(1, 60)

    public val maxCount: Int
        get() = mediaLimit

    public val mediaLibraryAction: String
        get() = params.optString("action", "pick").trim().lowercase().ifBlank { "pick" }

    public val mediaLimit: Int
        get() = params.optInt("limit", params.optInt("max_count", params.optInt("maxCount", 9))).coerceIn(1, 50)

    public val assetIds: List<String>
        get() {
            val raw = params.opt("asset_ids") ?: params.opt("assetIds") ?: return emptyList()
            val values = when (raw) {
                is JSONArray -> (0 until raw.length()).map { raw.optString(it) }
                else -> raw.toString().split(',')
            }
            return values.map { it.trim() }.filter { it.isNotEmpty() }
        }

    public val requestPermission: Boolean
        get() = params.opt("request_permission")?.let { it as? Boolean ?: it.toString().equals("true", ignoreCase = true) }
            ?: params.opt("requestPermission")?.let { it as? Boolean ?: it.toString().equals("true", ignoreCase = true) }
            ?: true

    public val startMs: Long?
        get() = optionalLong("start_ms") ?: optionalLong("startMs")

    public val endMs: Long?
        get() = optionalLong("end_ms") ?: optionalLong("endMs")

    public val mediaTypes: List<String>
        get() {
            val raw = params.opt("media_types") ?: params.opt("mediaTypes") ?: return listOf("image")
            val values = when (raw) {
                is JSONArray -> (0 until raw.length()).map { raw.optString(it) }
                else -> raw.toString().split(',')
            }
            return values
                .map { it.trim().lowercase() }
                .filter { it == "image" || it == "video" }
                .ifEmpty { listOf("image") }
        }

    private fun optionalLong(key: String): Long? = when (val value = params.opt(key)) {
        is Number -> value.toLong()
        is String -> value.trim().toLongOrNull()
        else -> null
    }
}

public data class AndroidPlatformToolContext(
    val filesDir: String?,
    val workspaceFilesDir: String?,
) {
    public val workspaceDir: String?
        get() {
            val base = workspaceFilesDir?.takeIf(String::isNotBlank) ?: filesDir
            return base?.takeIf(String::isNotBlank)?.let { "$it/linux-env/workspace" }
        }

    public val rootfsDir: String?
        get() = filesDir?.takeIf(String::isNotBlank)?.let { "$it/linux-env/rootfs" }

    public val skillsDir: String?
        get() = filesDir?.takeIf(String::isNotBlank)?.let { "$it/prompt_skills" }

    public fun ensureAttachmentDir(category: String): File? {
        val workspace = workspaceDir ?: return null
        return File(workspace, "attachments/$category").apply { mkdirs() }
    }

    public fun attachmentSandboxPath(category: String, filename: String): String =
        "/workspace/attachments/$category/$filename"

    public fun attachmentResultJson(
        sandboxPath: String,
        kind: String,
        filename: String,
        mimeType: String,
        sizeBytes: Long,
        extra: JSONObject = JSONObject(),
    ): String {
        val result = JSONObject()
            .put("sandbox_path", sandboxPath)
            .put("file_path", sandboxPath)
            .put("kind", kind)
            .put("filename", filename)
            .put("mime_type", mimeType)
            .put("mimeType", mimeType)
            .put("size_bytes", sizeBytes)
            .put("sizeBytes", sizeBytes)
        for (key in extra.keys()) {
            result.put(key, extra.get(key))
        }
        return result.toString()
    }

    public fun errorJson(message: String, includeSuccess: Boolean = false): String =
        JSONObject()
            .apply { if (includeSuccess) put("success", false) }
            .put("error", message)
            .toString()

    public fun resolveSandboxOrLocalPath(path: String): String {
        val workspace = workspaceDir
        val rootfs = rootfsDir
        val skills = skillsDir
        return when {
            path == "/workspace" && workspace != null -> workspace
            path.startsWith("/workspace/") && workspace != null ->
                "$workspace/${path.substring("/workspace/".length)}"
            path == "/skills" && skills != null -> skills
            path.startsWith("/skills/") && skills != null ->
                "$skills/${path.substring("/skills/".length)}"
            ROOTFS_PREFIXES.any { prefix -> path == prefix || path.startsWith("$prefix/") } && rootfs != null ->
                "$rootfs/${path.substring(1)}"
            else -> path
        }
    }

    public companion object {
        public fun from(context: Context, contextJson: String): AndroidPlatformToolContext {
            val json = runCatching { JSONObject(contextJson.ifBlank { "{}" }) }.getOrDefault(JSONObject())
            return AndroidPlatformToolContext(
                filesDir = json.optString("files_dir").takeIf(String::isNotBlank)
                    ?: context.filesDir.absolutePath,
                workspaceFilesDir = json.optString("workspace_files_dir").takeIf(String::isNotBlank),
            )
        }
    }
}

public data class AlarmSpec(
    val hour: Int,
    val minute: Int,
    val message: String,
    val repeatDays: List<Int> = emptyList(),
)

private fun parseInstantMillis(raw: String): Long? =
    try {
        Instant.parse(raw).toEpochMilli()
    } catch (_: DateTimeParseException) {
        null
    }

private fun millisToIso(millis: Long): String = Instant.ofEpochMilli(millis).toString()

private val ROOTFS_PREFIXES: List<String> = listOf(
    "/tmp",
    "/root",
    "/home",
    "/var",
    "/usr",
    "/opt",
    "/etc",
    "/srv",
    "/run",
)

private val REPEAT_DAY_PRESETS: Map<String, List<Int>> = mapOf(
    "daily" to listOf(1, 2, 3, 4, 5, 6, 7),
    "everyday" to listOf(1, 2, 3, 4, 5, 6, 7),
    "every day" to listOf(1, 2, 3, 4, 5, 6, 7),
    "all" to listOf(1, 2, 3, 4, 5, 6, 7),
    "每天" to listOf(1, 2, 3, 4, 5, 6, 7),
    "每日" to listOf(1, 2, 3, 4, 5, 6, 7),
    "weekdays" to listOf(2, 3, 4, 5, 6),
    "weekday" to listOf(2, 3, 4, 5, 6),
    "workdays" to listOf(2, 3, 4, 5, 6),
    "workday" to listOf(2, 3, 4, 5, 6),
    "工作日" to listOf(2, 3, 4, 5, 6),
    "weekends" to listOf(1, 7),
    "weekend" to listOf(1, 7),
    "周末" to listOf(1, 7),
)

private val REPEAT_DAY_ALIASES: Map<String, Int> = mapOf(
    "sunday" to 1,
    "sun" to 1,
    "周日" to 1,
    "星期日" to 1,
    "礼拜日" to 1,
    "周天" to 1,
    "星期天" to 1,
    "礼拜天" to 1,
    "monday" to 2,
    "mon" to 2,
    "周一" to 2,
    "星期一" to 2,
    "礼拜一" to 2,
    "tuesday" to 3,
    "tue" to 3,
    "tues" to 3,
    "周二" to 3,
    "星期二" to 3,
    "礼拜二" to 3,
    "wednesday" to 4,
    "wed" to 4,
    "周三" to 4,
    "星期三" to 4,
    "礼拜三" to 4,
    "thursday" to 5,
    "thu" to 5,
    "thur" to 5,
    "thurs" to 5,
    "周四" to 5,
    "星期四" to 5,
    "礼拜四" to 5,
    "friday" to 6,
    "fri" to 6,
    "周五" to 6,
    "星期五" to 6,
    "礼拜五" to 6,
    "saturday" to 7,
    "sat" to 7,
    "周六" to 7,
    "星期六" to 7,
    "礼拜六" to 7,
)
