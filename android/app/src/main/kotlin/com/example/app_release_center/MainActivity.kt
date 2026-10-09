package com.example.app_release_center

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt through AndroidX BiometricPrompt, which needs a
// FragmentActivity host. On a plain FlutterActivity the prompt never appears
// and authentication fails with no_fragment_activity.
class MainActivity : FlutterFragmentActivity()
