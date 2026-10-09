import 'dart:async';

import 'package:app_management_center/app/services/app_lock_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Stands in front of [child] while the app lock is engaged.
///
/// Built as a wrapper rather than a route so that locking on resume replaces
/// whatever is on screen without unwinding the navigation stack: coming back
/// to a running command should land back on that command, not on a fresh
/// console.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  AppLockService? get _lock =>
      Get.isRegistered<AppLockService>() ? Get.find<AppLockService>() : null;

  @override
  void initState() {
    super.initState();
    // Straight into the prompt on a cold start: a locked screen whose only
    // control is "unlock" should not need that button pressed first.
    if (_lock?.isLocked.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_unlock()));
    }
  }

  Future<void> _unlock() async {
    await _lock?.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final lock = _lock;
    if (lock == null) return widget.child;

    return Obx(() {
      if (!lock.isLocked.value) return widget.child;
      return _LockScreen(
        busy: lock.isPrompting.value,
        message: lock.status.value,
        onUnlock: _unlock,
      );
    });
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.busy,
    required this.message,
    required this.onUnlock,
  });

  final bool busy;
  final String message;
  final Future<void> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Management Remote đang khóa',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Dùng khuôn mặt, vân tay hoặc mã máy để mở.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: busy ? null : () => unawaited(onUnlock()),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: const Text('Mở khóa'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
