package com.example.app_release_center

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/// How a finished release sounds and feels on the phone.
///
/// Each outcome has its own channel because on Android 8+ a channel, not a
/// notification, owns the sound and the vibration pattern — and both are fixed
/// once the channel exists. Changing either means a new channel id, which is
/// why the ids carry a version.
object ReleaseNotifications {
    enum class Outcome(
        val channelId: String,
        val channelName: String,
        val channelDescription: String,
        val sound: Int,
        val vibration: LongArray,
        val color: Int,
    ) {
        SUCCEEDED(
            channelId = "release_success_v3",
            channelName = "Release thành công",
            channelDescription = "Luồng release chạy xong: chuông \"ting ting\" hai tiếng cao, rung hai nhịp nhẹ.",
            sound = R.raw.release_success,
            vibration = longArrayOf(0, 70, 90, 70),
            color = Color.parseColor("#22C55E"),
        ),
        FAILED(
            channelId = "release_failure_v3",
            channelName = "Release lỗi",
            channelDescription = "Luồng release dừng vì lỗi: ba tiếng chuông rơi dần xuống thấp, rung dài ba lần.",
            sound = R.raw.release_failure,
            vibration = longArrayOf(0, 450, 150, 450, 150, 900),
            color = Color.parseColor("#EF4444"),
        ),
    }

    /// Channels from earlier builds. A channel's sound cannot be changed once
    /// created, only the channel replaced: v1 pointed at sounds a release
    /// build had stripped, v2 carried the sounds before the "ting ting" set.
    private val retiredChannels = listOf(
        "release_success_v1",
        "release_failure_v1",
        "release_success_v2",
        "release_failure_v2",
    )

    /// Anything other than an explicit failure is a success: a test push, or a
    /// relay newer than this app, should still make a sound rather than none.
    fun outcomeOf(value: String?): Outcome =
        if (value == "failed") Outcome.FAILED else Outcome.SUCCEEDED

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        for (id in retiredChannels) manager.deleteNotificationChannel(id)
        val audio = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        for (outcome in Outcome.values()) {
            val channel = NotificationChannel(
                outcome.channelId,
                outcome.channelName,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = outcome.channelDescription
                setSound(soundUri(context, outcome), audio)
                enableVibration(true)
                vibrationPattern = outcome.vibration
                enableLights(true)
                lightColor = outcome.color
            }
            manager.createNotificationChannel(channel)
        }
    }

    /// Whether a notification posted now would be shown at all.
    fun canPost(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun show(context: Context, outcome: Outcome, title: String, body: String, tag: String?) {
        ensureChannels(context)
        if (!canPost(context)) return
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, outcome.channelId)
            .setSmallIcon(R.drawable.ic_stat_release)
            .setColor(outcome.color)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            // Below Android 8 the notification itself carries these.
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSound(soundUri(context, outcome))
            .setVibrate(outcome.vibration)
            .setLights(outcome.color, 600, 1200)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            NotificationManagerCompat.from(context)
                .notify(tag ?: outcome.channelId, 0, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post; nothing to show.
        }
    }

    /// Opens the system settings where the person can change the sound or
    /// vibration of one outcome, or of the app's notifications as a whole.
    fun settingsIntent(context: Context, outcome: Outcome?): Intent {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && outcome != null) {
            Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, outcome.channelId)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        } else {
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:${context.packageName}"))
        }
        return intent
            .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /// By resource id: a reference through R keeps the file in a shrunk
    /// release build, where a name inside a string would not.
    private fun soundUri(context: Context, outcome: Outcome): Uri =
        Uri.parse(
            "${ContentResolver.SCHEME_ANDROID_RESOURCE}://${context.packageName}/${outcome.sound}",
        )
}
