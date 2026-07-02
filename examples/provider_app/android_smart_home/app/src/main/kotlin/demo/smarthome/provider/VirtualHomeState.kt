package demo.smarthome.provider

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.time.Instant
import java.util.Date
import java.util.Locale

enum class DeviceKind { LIGHT, COVER, MEDIA, APPLIANCE, CLIMATE, SENSOR }

data class HomeDevice(
    val id: String,
    val name: String,
    val kind: DeviceKind,
    val on: Boolean = false,
    val brightness: Int = 0,
    val position: Int = 0,
    val mode: String? = null,
    val targetTempC: Int? = null,
    val statusText: String = "",
) {
    fun summary(): String = when (kind) {
        DeviceKind.LIGHT -> if (on) "$brightness%" else "关闭"
        DeviceKind.COVER -> if (position > 0) "已打开 · $position%" else "已关闭"
        DeviceKind.MEDIA -> if (on) "正在播放" else "已停止"
        DeviceKind.APPLIANCE -> if (on) "已开启" else "已关闭"
        DeviceKind.CLIMATE ->
            if (on) "${climateModeLabel(mode)} · ${targetTempC ?: 24}℃" else "已关闭"
        DeviceKind.SENSOR -> statusText.ifEmpty { "—" }
    }

    fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("kind", kind.name.lowercase())
        .put("on", on)
        .put("brightness", brightness)
        .put("position", position)
        .put("mode", mode ?: JSONObject.NULL)
        .put("target_temp_c", targetTempC ?: JSONObject.NULL)
        .put("status", statusText)
}

internal fun climateModeLabel(mode: String?): String = when (mode) {
    "cool" -> "制冷"
    "heat" -> "制热"
    "dry" -> "除湿"
    "fan" -> "送风"
    "auto" -> "自动"
    else -> "制冷"
}

data class HomeRoom(
    val id: String,
    val displayName: String,
    val tempC: Double,
    val humidity: Int,
    val devices: List<HomeDevice>,
) {
    fun replace(deviceId: String, transform: (HomeDevice) -> HomeDevice): HomeRoom =
        copy(devices = devices.map { if (it.id == deviceId) transform(it) else it })

    fun device(id: String): HomeDevice? = devices.firstOrNull { it.id == id }

    fun toJsonObject(): JSONObject = JSONObject()
        .put("display_name", displayName)
        .put("temp_c", tempC)
        .put("humidity", humidity)
        .put("devices", JSONArray(devices.map { it.toJsonObject() }))
}

data class EnergyMetrics(
    val evPlugged: Boolean = false,
    val lastChargeKwh: Double = 16.3,
    val homePowerWatts: Int = 787,
    val voltageV: Int = 232,
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("ev_plugged", evPlugged)
        .put("last_charge_kwh", lastChargeKwh)
        .put("home_power_w", homePowerWatts)
        .put("voltage_v", voltageV)
}

data class OutdoorSensors(
    val tempC: Double = 10.5,
    val humidity: Double = 70.4,
    val awayMode: Boolean = true,
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("temp_c", tempC)
        .put("humidity", humidity)
        .put("away", awayMode)
}

data class LogEntry(
    val timestampMs: Long,
    val message: String,
) {
    fun format(): String {
        val time = LOG_TIME_FORMAT.format(Date(timestampMs))
        return "[$time] $message"
    }

    companion object {
        private val LOG_TIME_FORMAT = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
    }
}

data class VirtualHomeState(
    val scene: String = "away",
    val rooms: List<HomeRoom> = defaultRooms(),
    val energy: EnergyMetrics = EnergyMetrics(),
    val outdoor: OutdoorSensors = OutdoorSensors(),
    val lastProposal: String = "等待 Agent",
    val lastResult: String = "暂无结果",
    val log: List<LogEntry> = emptyList(),
) {
    fun replaceRoom(roomId: String, transform: (HomeRoom) -> HomeRoom): VirtualHomeState =
        copy(rooms = rooms.map { if (it.id == roomId) transform(it) else it })

    fun room(id: String): HomeRoom? = rooms.firstOrNull { it.id == id }

    fun toResultJson(): String {
        val roomsObj = JSONObject()
        rooms.forEach { roomsObj.put(it.id, it.toJsonObject()) }
        return JSONObject()
            .put("scene", scene)
            .put("rooms", roomsObj)
            .put("energy", energy.toJsonObject())
            .put("outdoor", outdoor.toJsonObject())
            .put("timestamp", Instant.now().toString())
            .toString()
    }
}

private fun defaultRooms(): List<HomeRoom> = listOf(
    HomeRoom(
        id = "living_room",
        displayName = "客厅",
        tempC = 22.8,
        humidity = 57,
        devices = listOf(
            HomeDevice("floor_lamp", "落地灯", DeviceKind.LIGHT, on = false, brightness = 0),
            HomeDevice("spotlights", "射灯", DeviceKind.LIGHT, on = false, brightness = 0),
            HomeDevice("bar_lamp", "吧台灯", DeviceKind.LIGHT, on = false, brightness = 0),
            HomeDevice("blinds", "百叶窗", DeviceKind.COVER, position = 0),
            HomeDevice(
                "air_conditioner", "空调", DeviceKind.CLIMATE,
                on = false, mode = "off", targetTempC = 24,
            ),
            HomeDevice("nest_mini", "Nest 迷你音箱", DeviceKind.MEDIA, on = false),
        ),
    ),
    HomeRoom(
        id = "kitchen",
        displayName = "厨房",
        tempC = 21.4,
        humidity = 53,
        devices = listOf(
            HomeDevice("shutter", "卷帘", DeviceKind.COVER, position = 0),
            HomeDevice("spotlights", "厨房射灯", DeviceKind.LIGHT, on = false, brightness = 0),
            HomeDevice("worktop", "操作台", DeviceKind.APPLIANCE, on = false),
            HomeDevice(
                "fridge", "冰箱", DeviceKind.SENSOR,
                statusText = "已关闭",
            ),
            HomeDevice("nest_audio", "Nest 音响", DeviceKind.MEDIA, on = false),
        ),
    ),
)

object VirtualHomeStore {
    private const val PREFS = "virtual_smart_home"
    private const val KEY_STATE = "state_json"
    private const val LOG_LIMIT = 100

    fun load(context: Context): VirtualHomeState {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_STATE, null) ?: return VirtualHomeState()
        return runCatching { fromJson(raw) }.getOrElse { VirtualHomeState() }
    }

    fun save(context: Context, state: VirtualHomeState) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_STATE, toJson(state))
            .apply()
    }

    fun applyAction(
        context: Context,
        actionId: String,
        argsJson: String,
        source: String = "agent",
    ): VirtualHomeState {
        val current = load(context)
        val args = runCatching { JSONObject(argsJson) }.getOrElse { JSONObject() }
        val (next, logMessage) = when (actionId) {
            SmartHomePackage.ACTION_LIGHT_SET -> applyLightSet(current, args)
            SmartHomePackage.ACTION_COVER_SET -> applyCoverSet(current, args)
            SmartHomePackage.ACTION_MEDIA_TOGGLE -> applyMediaToggle(current, args)
            SmartHomePackage.ACTION_APPLIANCE_TOGGLE -> applyApplianceToggle(current, args)
            SmartHomePackage.ACTION_CLIMATE_SET -> applyClimateSet(current, args)
            SmartHomePackage.ACTION_SCENE_AWAY -> applySceneAway(current)
            SmartHomePackage.ACTION_SCENE_HOME -> applySceneHome(current)
            SmartHomePackage.ACTION_STATUS -> current.copy(lastResult = "已返回当前状态") to "读取当前状态"
            else -> current.copy(lastResult = "不支持的动作：$actionId") to "未知动作：$actionId"
        }
        val sourcePrefix = when (source) {
            "agent" -> "Agent"
            "home_agent" -> "家居助手"
            else -> "手动"
        }
        val withLog = prependLog(next, "[$sourcePrefix] $logMessage")
        save(context, withLog)
        return withLog
    }

    fun recordProposal(context: Context, actionId: String): VirtualHomeState {
        val next = load(context).copy(
            lastProposal = actionId,
            lastResult = "等待确认",
        )
        save(context, next)
        return next
    }

    fun recordAgentNote(context: Context, agentName: String, message: String): VirtualHomeState {
        val next = load(context).copy(
            lastProposal = agentName,
            lastResult = message,
        )
        val withLog = prependLog(next, "[$agentName] $message")
        save(context, withLog)
        return withLog
    }

    fun clearLog(context: Context): VirtualHomeState {
        val next = load(context).copy(log = emptyList())
        save(context, next)
        return next
    }

    private fun applyLightSet(
        state: VirtualHomeState,
        args: JSONObject,
    ): Pair<VirtualHomeState, String> {
        val roomId = args.optString("room")
        val deviceId = args.optString("device")
        val onProvided = args.has("on")
        val brightnessProvided = args.has("brightness")
        var deviceLabel = deviceId
        var roomLabel = roomId
        var summary = "—"
        val nextState = state.replaceRoom(roomId) { room ->
            roomLabel = room.displayName
            room.replace(deviceId) { device ->
                if (device.kind != DeviceKind.LIGHT) device
                else {
                    val newBrightness = if (brightnessProvided)
                        args.getInt("brightness").coerceIn(0, 100) else device.brightness
                    val newOn = if (onProvided) args.getBoolean("on")
                        else if (brightnessProvided) newBrightness > 0
                        else device.on
                    deviceLabel = device.name
                    val updated = device.copy(on = newOn, brightness = if (newOn) newBrightness else 0)
                    summary = if (newOn) "$newBrightness%" else "关闭"
                    updated
                }
            }
        }.copy(scene = "custom", lastResult = "灯 $roomId/$deviceId 已更新")
        return nextState to "$roomLabel · $deviceLabel → $summary"
    }

    private fun applyCoverSet(
        state: VirtualHomeState,
        args: JSONObject,
    ): Pair<VirtualHomeState, String> {
        val roomId = args.optString("room")
        val deviceId = args.optString("device")
        val position = args.optInt("position", 0).coerceIn(0, 100)
        var deviceLabel = deviceId
        var roomLabel = roomId
        val nextState = state.replaceRoom(roomId) { room ->
            roomLabel = room.displayName
            room.replace(deviceId) { device ->
                if (device.kind != DeviceKind.COVER) device
                else {
                    deviceLabel = device.name
                    device.copy(position = position)
                }
            }
        }.copy(scene = "custom", lastResult = "窗帘 $roomId/$deviceId → $position%")
        return nextState to "$roomLabel · $deviceLabel → ${if (position > 0) "$position%" else "已关闭"}"
    }

    private fun applyMediaToggle(
        state: VirtualHomeState,
        args: JSONObject,
    ): Pair<VirtualHomeState, String> {
        val roomId = args.optString("room")
        val deviceId = args.optString("device")
        val on = args.optBoolean("on", true)
        var deviceLabel = deviceId
        var roomLabel = roomId
        val nextState = state.replaceRoom(roomId) { room ->
            roomLabel = room.displayName
            room.replace(deviceId) { device ->
                if (device.kind != DeviceKind.MEDIA) device
                else {
                    deviceLabel = device.name
                    device.copy(on = on)
                }
            }
        }.copy(scene = "custom", lastResult = "媒体 $roomId/$deviceId 已${if (on) "播放" else "停止"}")
        return nextState to "$roomLabel · $deviceLabel → ${if (on) "正在播放" else "已停止"}"
    }

    private fun applyApplianceToggle(
        state: VirtualHomeState,
        args: JSONObject,
    ): Pair<VirtualHomeState, String> {
        val roomId = args.optString("room")
        val deviceId = args.optString("device")
        val on = args.optBoolean("on", true)
        var deviceLabel = deviceId
        var roomLabel = roomId
        val nextState = state.replaceRoom(roomId) { room ->
            roomLabel = room.displayName
            room.replace(deviceId) { device ->
                if (device.kind != DeviceKind.APPLIANCE) device
                else {
                    deviceLabel = device.name
                    device.copy(on = on)
                }
            }
        }.copy(scene = "custom", lastResult = "电器 $roomId/$deviceId → ${if (on) "开" else "关"}")
        return nextState to "$roomLabel · $deviceLabel → ${if (on) "已开启" else "已关闭"}"
    }

    private fun applyClimateSet(
        state: VirtualHomeState,
        args: JSONObject,
    ): Pair<VirtualHomeState, String> {
        val roomId = args.optString("room")
        val deviceId = args.optString("device")
        val mode = args.optString("mode", "cool").ifEmpty { "cool" }
        val targetTemp = if (args.has("target_temp"))
            args.optInt("target_temp").coerceIn(16, 30) else null
        val on = mode != "off"
        var deviceLabel = deviceId
        var roomLabel = roomId
        var summary = "已关闭"
        val nextState = state.replaceRoom(roomId) { room ->
            roomLabel = room.displayName
            room.replace(deviceId) { device ->
                if (device.kind != DeviceKind.CLIMATE) device
                else {
                    deviceLabel = device.name
                    val nextTemp = targetTemp ?: device.targetTempC ?: 24
                    summary = if (on) "${climateModeLabel(mode)} · ${nextTemp}℃" else "已关闭"
                    device.copy(on = on, mode = mode, targetTempC = nextTemp)
                }
            }
        }.copy(scene = "custom", lastResult = "空调 $roomId/$deviceId → $summary")
        return nextState to "$roomLabel · $deviceLabel → $summary"
    }

    private fun applySceneAway(state: VirtualHomeState): Pair<VirtualHomeState, String> =
        state.copy(
            scene = "away",
            rooms = state.rooms.map { room ->
                room.copy(devices = room.devices.map { device ->
                    when (device.kind) {
                        DeviceKind.LIGHT -> device.copy(on = false, brightness = 0)
                        DeviceKind.MEDIA -> device.copy(on = false)
                        DeviceKind.APPLIANCE -> device.copy(on = false)
                        DeviceKind.COVER -> device.copy(position = 0)
                        DeviceKind.CLIMATE -> device.copy(on = false, mode = "off")
                        DeviceKind.SENSOR -> device
                    }
                })
            },
            outdoor = state.outdoor.copy(awayMode = true),
            lastResult = "已切换至离家场景",
        ) to "场景：离家"

    private fun applySceneHome(state: VirtualHomeState): Pair<VirtualHomeState, String> {
        val nextRooms = state.rooms.map { room ->
            when (room.id) {
                "living_room" -> room.copy(devices = room.devices.map { device ->
                    when (device.id) {
                        "floor_lamp" -> device.copy(on = true, brightness = 70)
                        "spotlights" -> device.copy(on = true, brightness = 60)
                        "bar_lamp" -> device.copy(on = true, brightness = 100)
                        "blinds" -> device.copy(position = 100)
                        "air_conditioner" -> device.copy(on = true, mode = "cool", targetTempC = 24)
                        "nest_mini" -> device.copy(on = true)
                        else -> device
                    }
                })
                "kitchen" -> room.copy(devices = room.devices.map { device ->
                    when (device.id) {
                        "shutter" -> device.copy(position = 100)
                        "spotlights" -> device.copy(on = true, brightness = 80)
                        "worktop" -> device.copy(on = false)
                        "nest_audio" -> device.copy(on = true)
                        else -> device
                    }
                })
                else -> room
            }
        }
        return state.copy(
            scene = "home",
            rooms = nextRooms,
            outdoor = state.outdoor.copy(awayMode = false),
            lastResult = "已切换至回家场景",
        ) to "场景：回家"
    }

    private fun prependLog(state: VirtualHomeState, message: String): VirtualHomeState {
        val entry = LogEntry(System.currentTimeMillis(), message)
        val merged = (listOf(entry) + state.log).take(LOG_LIMIT)
        return state.copy(log = merged)
    }

    private fun toJson(state: VirtualHomeState): String {
        val obj = JSONObject()
            .put("scene", state.scene)
            .put("last_proposal", state.lastProposal)
            .put("last_result", state.lastResult)
            .put("energy", state.energy.toJsonObject())
            .put("outdoor", state.outdoor.toJsonObject())
        val rooms = JSONArray()
        state.rooms.forEach { room ->
            val roomObj = JSONObject()
                .put("id", room.id)
                .put("display_name", room.displayName)
                .put("temp_c", room.tempC)
                .put("humidity", room.humidity)
            val devices = JSONArray()
            room.devices.forEach { device ->
                devices.put(
                    JSONObject()
                        .put("id", device.id)
                        .put("name", device.name)
                        .put("kind", device.kind.name)
                        .put("on", device.on)
                        .put("brightness", device.brightness)
                        .put("position", device.position)
                        .put("mode", device.mode ?: JSONObject.NULL)
                        .put("target_temp_c", device.targetTempC ?: JSONObject.NULL)
                        .put("status", device.statusText),
                )
            }
            roomObj.put("devices", devices)
            rooms.put(roomObj)
        }
        obj.put("rooms", rooms)
        val logArr = JSONArray()
        state.log.forEach { entry ->
            logArr.put(
                JSONObject()
                    .put("ts", entry.timestampMs)
                    .put("msg", entry.message),
            )
        }
        obj.put("log", logArr)
        return obj.toString()
    }

    private fun fromJson(raw: String): VirtualHomeState {
        val obj = JSONObject(raw)
        val rooms = mutableListOf<HomeRoom>()
        val arr = obj.optJSONArray("rooms") ?: JSONArray()
        for (i in 0 until arr.length()) {
            val r = arr.getJSONObject(i)
            val devicesArr = r.optJSONArray("devices") ?: JSONArray()
            val devices = mutableListOf<HomeDevice>()
            for (j in 0 until devicesArr.length()) {
                val d = devicesArr.getJSONObject(j)
                devices += HomeDevice(
                    id = d.optString("id"),
                    name = d.optString("name"),
                    kind = runCatching { DeviceKind.valueOf(d.optString("kind", "SENSOR")) }
                        .getOrDefault(DeviceKind.SENSOR),
                    on = d.optBoolean("on"),
                    brightness = d.optInt("brightness"),
                    position = d.optInt("position"),
                    mode = if (d.has("mode") && !d.isNull("mode")) d.optString("mode") else null,
                    targetTempC = if (d.has("target_temp_c") && !d.isNull("target_temp_c"))
                        d.optInt("target_temp_c") else null,
                    statusText = d.optString("status"),
                )
            }
            rooms += HomeRoom(
                id = r.optString("id"),
                displayName = r.optString("display_name"),
                tempC = r.optDouble("temp_c", 0.0),
                humidity = r.optInt("humidity"),
                devices = devices,
            )
        }
        val energyObj = obj.optJSONObject("energy") ?: JSONObject()
        val outdoorObj = obj.optJSONObject("outdoor") ?: JSONObject()
        val logArr = obj.optJSONArray("log") ?: JSONArray()
        val log = mutableListOf<LogEntry>()
        for (i in 0 until logArr.length()) {
            val e = logArr.getJSONObject(i)
            log += LogEntry(
                timestampMs = e.optLong("ts"),
                message = e.optString("msg"),
            )
        }
        return VirtualHomeState(
            scene = obj.optString("scene", "default"),
            rooms = if (rooms.isEmpty()) defaultRooms() else rooms,
            energy = EnergyMetrics(
                evPlugged = energyObj.optBoolean("ev_plugged", false),
                lastChargeKwh = energyObj.optDouble("last_charge_kwh", 16.3),
                homePowerWatts = energyObj.optInt("home_power_w", 787),
                voltageV = energyObj.optInt("voltage_v", 232),
            ),
            outdoor = OutdoorSensors(
                tempC = outdoorObj.optDouble("temp_c", 10.5),
                humidity = outdoorObj.optDouble("humidity", 70.4),
                awayMode = outdoorObj.optBoolean("away", true),
            ),
            lastProposal = obj.optString("last_proposal", "等待 Agent"),
            lastResult = obj.optString("last_result", "暂无结果"),
            log = log,
        )
    }
}
