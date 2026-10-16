package com.example.app_release_center

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/// Receives release pushes while the app is in the foreground.
///
/// When the app is in the background or not running, Firebase shows the
/// notification itself on the channel the relay names, so the sound and the
/// vibration are the same either way.
class ReleasePushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = message.notification?.title ?: data["title"] ?: return
        val body = message.notification?.body ?: data["body"] ?: ""
        ReleaseNotifications.show(
            this,
            ReleaseNotifications.outcomeOf(data["outcome"]),
            title,
            body,
            data["tag"],
        )
    }

    /// The app registers whatever token it has each time it starts, so a token
    /// that changes while it is closed is picked up on the next launch.
    override fun onNewToken(token: String) = Unit
}
