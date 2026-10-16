package com.example.app_release_center

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt through AndroidX BiometricPrompt, which needs a
// FragmentActivity host. On a plain FlutterActivity the prompt never appears
// and authentication fails with no_fragment_activity.
class MainActivity : FlutterFragmentActivity() {
    private var pendingPermission: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Created up front so a push that arrives while the app is closed
        // already finds the channel, and with it the right sound.
        ReleaseNotifications.ensureChannels(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "amc/release_push")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "available" to FirebaseApp.getApps(this).isNotEmpty(),
                            "canPost" to ReleaseNotifications.canPost(this),
                        ),
                    )
                    "requestPermission" -> requestPermission(result)
                    "token" -> token(result)
                    "deleteToken" -> deleteToken(result)
                    "test" -> {
                        val outcome = ReleaseNotifications.outcomeOf(call.argument<String>("outcome"))
                        ReleaseNotifications.show(
                            this,
                            outcome,
                            call.argument<String>("title") ?: "AMC",
                            call.argument<String>("body") ?: "",
                            "test-${outcome.channelId}",
                        )
                        result.success(ReleaseNotifications.canPost(this))
                    }
                    "openSettings" -> {
                        val outcome = call.argument<String>("outcome")
                            ?.let { ReleaseNotifications.outcomeOf(it) }
                        startActivity(ReleaseNotifications.settingsIntent(this, outcome))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(ReleaseNotifications.canPost(this))
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        pendingPermission?.success(ReleaseNotifications.canPost(this))
        pendingPermission = null
    }

    private fun token(result: MethodChannel.Result) {
        if (FirebaseApp.getApps(this).isEmpty()) {
            result.error("unavailable", "Firebase chưa được cấu hình cho bản app này.", null)
            return
        }
        FirebaseMessaging.getInstance().token
            .addOnSuccessListener { result.success(it) }
            .addOnFailureListener { result.error("token", it.message, null) }
    }

    private fun deleteToken(result: MethodChannel.Result) {
        if (FirebaseApp.getApps(this).isEmpty()) {
            result.success(null)
            return
        }
        FirebaseMessaging.getInstance().deleteToken()
            .addOnSuccessListener { result.success(null) }
            .addOnFailureListener { result.error("token", it.message, null) }
    }

    private companion object {
        const val PERMISSION_REQUEST = 4207
    }
}
