package com.jcm.closer

import android.Manifest
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jcm.closer/device_status")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") result.notImplemented()
                else try { result.success(DeviceStatus.read(this)) }
                catch (error: Exception) { result.error("unavailable", "Device status unavailable", null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jcm.closer/place_search")
            .setMethodCallHandler { call, result ->
                if (call.method != "search") result.notImplemented()
                else {
                    val query = call.argument<String>("query").orEmpty().take(300)
                    Thread {
                        try {
                            @Suppress("DEPRECATION")
                            val matches = android.location.Geocoder(this).getFromLocationName(query, 5).orEmpty()
                            val places = matches.map { mapOf("name" to (it.getAddressLine(0) ?: query), "lat" to it.latitude, "lon" to it.longitude) }
                            runOnUiThread { result.success(places) }
                        } catch (error: Exception) {
                            runOnUiThread { result.error("search_failed", "Place search unavailable", null) }
                        }
                    }.start()
                }
            }
        CallAudioBridge(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jcm.closer/distance")
            .setMethodCallHandler { call, result ->
                if (call.method == "show") {
                    try {
                        CoupleDistanceNotification.show(this, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("notification_failed", "Could not update distance notification", null)
                    }
                } else result.notImplemented()
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "requestLocationNotification") {
                    requestLocationNotification(result)
                    return@setMethodCallHandler
                }
                if (call.method != "syncWidget") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val data = call.arguments as? Map<*, *>
                if (data == null) {
                    result.error("bad_arguments", "Widget data was missing.", null)
                    return@setMethodCallHandler
                }

                val preferences = getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
                val clearOnly = data["clearLocation"] == true
                val paired = if (clearOnly) preferences.getBoolean("paired", false)
                    else data["paired"] as? Boolean ?: false
                val name = if (clearOnly) preferences.getString("name", "").orEmpty()
                    else data["name"] as? String ?: ""
                val partner = if (clearOnly) preferences.getString("partner", "").orEmpty()
                    else data["partner"] as? String ?: ""
                val clearLocation = !paired || clearOnly
                val locationShared = !clearLocation && data["locationShared"] == true
                val distance = when {
                    clearLocation -> -1f
                    locationShared -> (data["distanceMeters"] as? Number)?.toFloat() ?: -1f
                    else -> preferences.getFloat("distanceMeters", -1f)
                }
                val updatedAt = when {
                    clearLocation -> 0L
                    locationShared -> (data["updatedAt"] as? Number)?.toLong() ?: 0L
                    else -> preferences.getLong("updatedAt", 0L)
                }
                val changed = preferences.getBoolean("paired", false) != paired ||
                    preferences.getString("name", "") != name ||
                    preferences.getString("partner", "") != partner ||
                    preferences.getFloat("distanceMeters", -1f) != distance ||
                    preferences.getLong("updatedAt", 0L) != updatedAt ||
                    preferences.getBoolean("locationShared", false) != locationShared
                preferences.edit()
                    .putBoolean("paired", paired)
                    .putString("name", name)
                    .putString("partner", partner)
                    .putFloat("distanceMeters", distance)
                    .putLong("updatedAt", updatedAt)
                    .putBoolean("locationShared", locationShared)
                    .apply()

                val manager = AppWidgetManager.getInstance(this)
                val provider = ComponentName(this, CloserWidgetProvider::class.java)
                val widgetIds = manager.getAppWidgetIds(provider)
                val lastRender = preferences.getLong("lastRenderAt", 0L)
                if (changed || System.currentTimeMillis() - lastRender >= 15 * 60 * 1000L) {
                    widgetIds.forEach { id ->
                        CloserWidgetProvider.updateWidget(this, manager, id)
                    }
                    preferences.edit().putLong("lastRenderAt", System.currentTimeMillis()).apply()
                }
                result.success(null)
            }
    }

    private fun requestLocationNotification(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error("permission_in_progress", "Notification permission request is already open.", null)
            return
        }
        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    @Deprecated("Deprecated by Android, retained for the permission callback")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            notificationPermissionResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
            )
            notificationPermissionResult = null
        }
    }

    companion object {
        const val WIDGET_CHANNEL = "com.jcm.closer/widget"
        const val WIDGET_PREFS = "closer_widget"
        private const val NOTIFICATION_PERMISSION_REQUEST = 7412
    }
}
