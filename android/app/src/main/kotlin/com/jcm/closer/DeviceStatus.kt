package com.jcm.closer

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

object DeviceStatus {
    fun read(context: Context): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = manager.getNetworkCapabilities(manager.activeNetwork)
        val connection = when {
            caps == null -> "offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
        return mapOf("battery" to if (level >= 0 && scale > 0) (level * 100 / scale) else null,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL),
            "connection" to connection)
    }
}
