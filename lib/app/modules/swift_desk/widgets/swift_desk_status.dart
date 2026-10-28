import 'dart:async';
import 'package:flutter/material.dart';
import '../services/swift_desk_runtime.dart';

class SwiftDeskGlobalStatus extends StatelessWidget {
  const SwiftDeskGlobalStatus({super.key, required this.onOpen});
  final VoidCallback onOpen;
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<SwiftDeskRuntime?>(
    valueListenable: SwiftDeskRuntime.current,
    builder: (context, runtime, _) => runtime == null
        ? const SizedBox.shrink()
        : ListenableBuilder(
            listenable: runtime,
            builder: (context, _) {
              if (!runtime.hostEnabled && !runtime.active) {
                return const SizedBox.shrink();
              }
              final pending = runtime.pendingRequest;
              return Material(
                color: pending != null
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.connected_tv_outlined, size: 20),
                        Text(
                          pending != null
                              ? 'SwiftDesk: ${pending.name} muốn kết nối máy này'
                              : 'SwiftDesk: ${runtime.status}',
                        ),
                        TextButton(
                          onPressed: onOpen,
                          child: const Text('Mở SwiftDesk'),
                        ),
                        if (pending != null) ...[
                          FilledButton.tonal(
                            onPressed: () => runtime.accept(),
                            child: const Text('Cho xem màn hình'),
                          ),
                          TextButton(
                            onPressed: runtime.reject,
                            child: const Text('Từ chối'),
                          ),
                        ],
                        if (runtime.active && pending == null)
                          FilledButton.tonal(
                            onPressed: () => unawaited(runtime.disconnect()),
                            child: const Text('Ngắt ngay'),
                          ),
                        if (!runtime.active && runtime.hostEnabled)
                          TextButton(
                            onPressed: () => unawaited(runtime.disableHost()),
                            child: const Text('Tắt nhận kết nối'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
  );
}
