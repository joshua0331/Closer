package com.jcm.closer

import android.Manifest
import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.*
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat

object CoupleDistanceNotification {
    fun show(context: Context, data: Map<*, *>) {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = "closer_distance_channel"
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel, "Closer distance updates", NotificationManager.IMPORTANCE_LOW))
        val view = RemoteViews(context.packageName, R.layout.couple_distance_notification)
        val yours = data["yourName"] as? String ?: "You"
        val partner = data["partnerName"] as? String ?: "Your partner"
        view.setTextViewText(R.id.distance_you_name, yours)
        view.setTextViewText(R.id.distance_partner_name, partner)
        view.setTextViewText(R.id.distance_value, "Our distance: " + (data["distance"] as? String ?: ""))
        view.setTextViewText(R.id.distance_anniversary, data["together"] as? String ?: "Together with you")
        view.setImageViewBitmap(R.id.distance_you_avatar, avatar(data["yourAvatar"] as? String, yours))
        view.setImageViewBitmap(R.id.distance_partner_avatar, avatar(data["partnerAvatar"] as? String, partner))
        val intent = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_distance_notification)
            .setContentTitle("Closer · Our distance")
            .setContentText(data["together"] as? String ?: "")
            .setCustomContentView(view).setCustomBigContentView(view)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setContentIntent(intent).setOngoing(true).setOnlyAlertOnce(true)
            .setShowWhen(false).setSilent(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_LOW).build()
        manager.notify(888, notification)
    }

    private fun avatar(path: String?, name: String): Bitmap {
        val size = 128
        val result = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.rgb(234, 145, 119)
        canvas.drawCircle(64f, 64f, 62f, paint)
        val source = if (path.isNullOrBlank()) null else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val options = BitmapFactory.Options().apply { inSampleSize = maxOf(1, minOf(bounds.outWidth, bounds.outHeight) / size) }
            BitmapFactory.decodeFile(path, options)
        }
        if (source != null) {
            val shader = BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val scale = size.toFloat() / minOf(source.width, source.height)
            val matrix = Matrix().apply {
                setScale(scale, scale)
                postTranslate((size - source.width * scale) / 2, (size - source.height * scale) / 2)
            }
            shader.setLocalMatrix(matrix); paint.shader = shader
            canvas.drawCircle(64f, 64f, 60f, paint)
            paint.shader = null
            source.recycle()
        } else {
            paint.color = Color.WHITE; paint.textSize = 52f; paint.textAlign = Paint.Align.CENTER
            canvas.drawText(name.take(1).uppercase(), 64f, 64f - (paint.ascent() + paint.descent()) / 2, paint)
        }
        paint.color = Color.WHITE; paint.style = Paint.Style.STROKE; paint.strokeWidth = 3f
        canvas.drawCircle(64f, 64f, 61f, paint)
        return result
    }
}
