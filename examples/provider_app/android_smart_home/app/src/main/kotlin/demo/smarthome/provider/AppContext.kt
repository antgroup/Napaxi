package demo.smarthome.provider

import android.app.Application
import android.content.Context

class SmartHomeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppContext.context = this
    }
}

object AppContext {
    lateinit var context: Context

    fun require(): Context = context
}
