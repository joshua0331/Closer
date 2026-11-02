package com.jcm.closer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CloserWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
    }

    companion object {
        private const val FRESH_FOR_MS = 15 * 60 * 1000L

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = context.getSharedPreferences(MainActivity.WIDGET_PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.closer_widget)
            val launch = PendingIntent.getActivity(
                context,
                widgetId,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, launch)

            if (!prefs.getBoolean("paired", false)) {
                setState(views, "SETUP", 0xFF8C5948.toInt())
                views.setTextViewText(R.id.widget_names, "Your space for two")
                views.setTextViewText(R.id.widget_distance, "Open Closer to pair")
                views.setTextViewTextSize(R.id.widget_distance, TypedValue.COMPLEX_UNIT_SP, 16f)
                views.setTextViewText(R.id.widget_status, "Your shared space starts with two")
            } else {
                val yourName = prefs.getString("name", "You").orEmpty().ifBlank { "You" }
                val partnerName = prefs.getString("partner", "Partner").orEmpty().ifBlank { "Partner" }
                views.setTextViewText(R.id.widget_names, "$yourName  ♥  $partnerName")
                val distance = prefs.getFloat("distanceMeters", -1f).toDouble()
                val locationShared = prefs.getBoolean("locationShared", false)
                val updatedAt = prefs.getLong("updatedAt", 0L)
                val age = if (updatedAt > 0L) System.currentTimeMillis() - updatedAt else Long.MAX_VALUE

                if (distance >= 0 && age in 0..FRESH_FOR_MS) {
                    val badge = if (locationShared) {
                        "SHARING" to 0xFF527B5B.toInt()
                    } else {
                        "PAUSED" to 0xFFAD604C.toInt()
                    }
                    setState(views, badge.first, badge.second)
                    views.setTextViewTextSize(R.id.widget_distance, TypedValue.COMPLEX_UNIT_SP, 38f)
                    val value = distance / 1000.0
                    val distanceText = if (value < 1.0) {
                        "${distance.toInt()} m"
                    } else if (value >= 10) {
                        String.format(java.util.Locale.getDefault(), "%.0f km", value)
                    } else {
                        String.format(java.util.Locale.getDefault(), "%.1f km", value)
                    }
                    views.setTextViewText(R.id.widget_distance, distanceText)
                    val status = if (locationShared) {
                        "Updated ${formatTime(updatedAt)} · tap to open map"
                    } else {
                        "Last shared ${formatTime(updatedAt)} · sharing paused"
                    }
                    views.setTextViewText(R.id.widget_status, status)
                } else if (distance >= 0) {
                    setState(views, "OUTDATED", 0xFF8C5948.toInt())
                    views.setTextViewText(R.id.widget_distance, "Location is out of date")
                    views.setTextViewTextSize(R.id.widget_distance, TypedValue.COMPLEX_UNIT_SP, 16f)
                    views.setTextViewText(R.id.widget_status, "Open Closer to share a fresh location")
                } else {
                    setState(views, "READY", 0xFF8C5948.toInt())
                    views.setTextViewText(R.id.widget_distance, "Share locations to see your distance")
                    views.setTextViewTextSize(R.id.widget_distance, TypedValue.COMPLEX_UNIT_SP, 16f)
                    views.setTextViewText(R.id.widget_status, "Share from both phones to see distance")
                }
            }

            manager.updateAppWidget(widgetId, views)
        }

        private fun formatTime(timestamp: Long): String =
            SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date(timestamp))

        private fun setState(views: RemoteViews, label: String, color: Int) {
            views.setTextViewText(R.id.widget_state, label)
            views.setTextColor(R.id.widget_state, color)
        }
    }
}
