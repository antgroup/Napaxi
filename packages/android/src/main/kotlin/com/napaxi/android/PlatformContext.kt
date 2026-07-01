package com.napaxi.android

import android.content.Context
import org.json.JSONObject
import java.util.TimeZone

public data class NapaxiPlatformContext(
    val filesDir: String,
    val platformContextJson: String,
    val userTimezone: String? = null,
)

public object NapaxiPlatformContextResolver {
    @JvmStatic
    public fun resolve(context: Context): NapaxiPlatformContext {
        val appContext = context.applicationContext
        val filesDir = appContext.filesDir.absolutePath
        val userTimezone = TimeZone.getDefault().id
        val platformContext = JSONObject()
            .put("platform", "android")
            .put("files_dir", filesDir)
            .put("native_library_dir", appContext.applicationInfo.nativeLibraryDir)
            .put("user_timezone", userTimezone)
        return NapaxiPlatformContext(
            filesDir = filesDir,
            platformContextJson = platformContext.toString(),
            userTimezone = userTimezone,
        )
    }
}
