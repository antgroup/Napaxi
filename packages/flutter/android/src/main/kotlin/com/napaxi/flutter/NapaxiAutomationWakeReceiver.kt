package com.napaxi.flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NapaxiAutomationWakeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != NapaxiAutomationScheduler.ACTION_WAKE) return
        NapaxiAutomationScheduler.recordWake(context, intent)
        NapaxiAgentService.startAutomationWake(context)
    }
}
