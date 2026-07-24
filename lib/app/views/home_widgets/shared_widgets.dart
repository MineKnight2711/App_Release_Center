part of '../home_view.dart';

class GlobalCommandProgress extends StatefulWidget {
  const GlobalCommandProgress({super.key, required this.runner});

  final ReleaseRunnerService runner;

  @override
  State<GlobalCommandProgress> createState() => _GlobalCommandProgressState();
}

class _GlobalCommandProgressState extends State<GlobalCommandProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _chargeController;
  bool _shouldAnimate = false;

  @override
  void initState() {
    super.initState();
    _chargeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
  }

  @override
  void dispose() {
    _chargeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final runner = widget.runner;
      final progress = runner.overallProgress.value.clamp(0.0, 1.0);
      final currentStep = runner.workflowStep.value;
      final totalSteps = runner.workflowTotalSteps.value;
      final isRunning =
          runner.isWorkflowRunning.value || runner.isRunning.value;
      final isCompleted = !isRunning && progress >= 1;
      final isFailed = !isRunning && runner.status.value == 'Failed';
      final accentColor = isFailed
          ? Theme.of(context).colorScheme.error
          : isCompleted
          ? AppCyberTheme.neonGreen
          : isRunning
          ? AppCyberTheme.electricBlue
          : AppCyberTheme.textMuted;
      final stepText = totalSteps > 0
          ? 'STEP $currentStep/$totalSteps'
          : 'READY';
      final percent = '${(progress * 100).round()}%';
      _syncChargeAnimation(isRunning);

      return Semantics(
        container: true,
        label: runner.overallProgressLabel.value,
        value: percent,
        child: Container(
          key: const Key('global-command-progress'),
          height: 58,
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
          decoration: BoxDecoration(
            color: AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(
                color: accentColor.withValues(
                  alpha: AppCyberTheme.isCyber ? 0.5 : 0.28,
                ),
              ),
            ),
            boxShadow: AppCyberTheme.isCyber && isRunning
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              AnimatedBuilder(
                animation: _chargeController,
                builder: (context, child) {
                  final phase = _chargeController.value;
                  final pulse = isRunning
                      ? 0.94 + (1 - (phase * 2 - 1).abs()) * 0.1
                      : 1.0;
                  return Transform.scale(
                    scale: pulse,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accentColor.withValues(
                          alpha: AppCyberTheme.isCyber ? 0.12 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.45),
                        ),
                      ),
                      child: SizedBox.square(
                        dimension: 34,
                        child: Icon(
                          isFailed
                              ? Icons.error_outline_rounded
                              : isCompleted
                              ? Icons.check_rounded
                              : isRunning
                              ? Icons.bolt_rounded
                              : Icons.battery_0_bar_rounded,
                          size: 20,
                          color: accentColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            runner.overallProgressLabel.value,
                            key: const Key('global-command-progress-label'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppCyberTheme.dataTextStyle(
                              size: 10.6,
                              color: isRunning
                                  ? AppCyberTheme.textPrimary
                                  : AppCyberTheme.textMuted,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$stepText  |  $percent',
                          key: const Key('global-command-progress-value'),
                          style: AppCyberTheme.dataTextStyle(
                            size: 10.2,
                            color: accentColor,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: progress),
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      builder: (context, animatedProgress, child) {
                        return AnimatedBuilder(
                          animation: _chargeController,
                          builder: (context, child) => CustomPaint(
                            key: const Key('global-command-battery-track'),
                            painter: _BatteryChargePainter(
                              progress: animatedProgress,
                              phase: _chargeController.value,
                              accentColor: accentColor,
                              trackColor: AppCyberTheme.isCyber
                                  ? AppCyberTheme.electricBlue.withValues(
                                      alpha: 0.09,
                                    )
                                  : AppCyberTheme.lineBlue.withValues(
                                      alpha: 0.35,
                                    ),
                              isCharging: isRunning,
                            ),
                            child: const SizedBox(
                              width: double.infinity,
                              height: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  void _syncChargeAnimation(bool shouldAnimate) {
    if (_shouldAnimate == shouldAnimate) return;
    _shouldAnimate = shouldAnimate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shouldAnimate != shouldAnimate) return;
      if (shouldAnimate) {
        _chargeController.repeat();
      } else {
        _chargeController
          ..stop()
          ..value = 0;
      }
    });
  }
}

class _BatteryChargePainter extends CustomPainter {
  const _BatteryChargePainter({
    required this.progress,
    required this.phase,
    required this.accentColor,
    required this.trackColor,
    required this.isCharging,
  });

  final double progress;
  final double phase;
  final Color accentColor;
  final Color trackColor;
  final bool isCharging;

  @override
  void paint(Canvas canvas, Size size) {
    const terminalWidth = 4.0;
    const terminalGap = 2.0;
    final bodyWidth = size.width - terminalWidth - terminalGap;
    if (bodyWidth <= 6 || size.height <= 4) return;

    final bodyRect = Rect.fromLTWH(0, 0, bodyWidth, size.height);
    final bodyRRect = RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(3),
    );
    canvas.drawRRect(bodyRRect, Paint()..color = trackColor);
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = accentColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final terminalRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        bodyWidth + terminalGap,
        size.height * 0.3,
        terminalWidth,
        size.height * 0.4,
      ),
      const Radius.circular(1),
    );
    canvas.drawRRect(
      terminalRect,
      Paint()..color = accentColor.withValues(alpha: 0.65),
    );

    final innerRect = bodyRect.deflate(2.5);
    if (innerRect.width <= 0 || innerRect.height <= 0) return;
    const gap = 2.0;
    final segmentCount = ((innerRect.width + gap) / 18).floor().clamp(4, 28);
    final segmentWidth =
        (innerRect.width - gap * (segmentCount - 1)) / segmentCount;
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final waveCenter = phase * (segmentCount + 4) - 2;

    canvas.save();
    canvas.clipRRect(bodyRRect);
    for (var index = 0; index < segmentCount; index++) {
      final segmentStart = index / segmentCount;
      final segmentEnd = (index + 1) / segmentCount;
      final fillFraction =
          ((normalizedProgress - segmentStart) / (segmentEnd - segmentStart))
              .clamp(0.0, 1.0);
      final left = innerRect.left + index * (segmentWidth + gap);
      final cellRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, innerRect.top, segmentWidth, innerRect.height),
        const Radius.circular(1.5),
      );

      if (fillFraction > 0) {
        final filledRect = Rect.fromLTWH(
          left,
          innerRect.top,
          segmentWidth * fillFraction,
          innerRect.height,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(filledRect, const Radius.circular(1.5)),
          Paint()..color = accentColor.withValues(alpha: 0.86),
        );
      }

      if (isCharging) {
        final distance = (index - waveCenter).abs();
        final waveStrength = (1 - distance / 2.2).clamp(0.0, 1.0);
        if (waveStrength > 0) {
          canvas.drawRRect(
            cellRect,
            Paint()
              ..color = accentColor.withValues(
                alpha: 0.08 + waveStrength * 0.42,
              ),
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BatteryChargePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        phase != oldDelegate.phase ||
        accentColor != oldDelegate.accentColor ||
        trackColor != oldDelegate.trackColor ||
        isCharging != oldDelegate.isCharging;
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (!AppCyberTheme.isCyber) {
      return Container(
        padding: padding,
        decoration: AppCyberTheme.panelDecoration(),
        child: child,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: AppCyberTheme.panelDecoration(),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _ScanlinePainter(
                        color: AppCyberTheme.electricBlue.withValues(
                          alpha: 0.08,
                        ),
                        spacing: 12,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CornerBracketPainter(
                      color: AppCyberTheme.electricBlue.withValues(alpha: 0.55),
                      inset: 5,
                      bracketLength: 10,
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudCardShell extends StatelessWidget {
  const _HudCardShell({
    required this.child,
    this.active = false,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final bool active;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return _PulseGlow(
      enabled: active && AppCyberTheme.isCyber,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: AppCyberTheme.gridShellDecoration(active: active),
        child: Stack(
          children: [
            if (AppCyberTheme.isCyber) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _ScanlinePainter(
                        color: AppCyberTheme.electricBlue.withValues(
                          alpha: 0.1,
                        ),
                        spacing: 11,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CornerBracketPainter(
                      color: AppCyberTheme.electricBlue.withValues(alpha: 0.75),
                      inset: 4,
                      bracketLength: 8,
                    ),
                  ),
                ),
              ),
            ],
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            letterSpacing: 0.8,
            color: AppCyberTheme.isCyber
                ? AppCyberTheme.electricBlue.withValues(alpha: 0.95)
                : AppCyberTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.running});

  final String label;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final borderColor = AppCyberTheme.isCyber
        ? (running
              ? AppCyberTheme.neonGreen.withValues(alpha: 0.72)
              : AppCyberTheme.electricBlue.withValues(alpha: 0.45))
        : AppCyberTheme.lineBlue;
    final backgroundColor = AppCyberTheme.isCyber
        ? (running
              ? AppCyberTheme.neonGreen.withValues(alpha: 0.14)
              : AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.85))
        : AppCyberTheme.panelBackgroundStrong;
    final signalColor = running
        ? AppCyberTheme.neonGreen
        : AppCyberTheme.isCyber
        ? AppCyberTheme.electricBlue.withValues(alpha: 0.9)
        : AppCyberTheme.textMuted;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
        boxShadow: AppCyberTheme.isCyber
            ? [
                BoxShadow(
                  color:
                      (running
                              ? AppCyberTheme.neonGreen
                              : AppCyberTheme.electricBlue)
                          .withValues(alpha: 0.22),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
              ]
            : const [],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (running)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    AppCyberTheme.neonGreen.withValues(alpha: 0.95),
                  ),
                ),
              )
            else
              Icon(Icons.circle, size: 10, color: signalColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppCyberTheme.dataTextStyle(
                  size: 11.5,
                  color: AppCyberTheme.textPrimary,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwitchMenu extends StatelessWidget {
  const _ThemeSwitchMenu();

  @override
  Widget build(BuildContext context) {
    final themeService = Get.find<ThemeService>();

    return Obx(() {
      final selected = themeService.choice.value;

      return PopupMenuButton<AppThemeChoice>(
        tooltip: 'Switch theme',
        initialValue: selected,
        onSelected: themeService.setChoice,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: AppCyberTheme.panelBackgroundStrong,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: AppCyberTheme.isCyber
                ? AppCyberTheme.electricBlue.withValues(alpha: 0.35)
                : AppCyberTheme.lineBlue,
          ),
        ),
        itemBuilder: (context) => AppThemeChoice.values.map((choice) {
          return PopupMenuItem<AppThemeChoice>(
            value: choice,
            child: Row(
              children: [
                Icon(
                  choice == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                ),
                const SizedBox(width: 10),
                Icon(choice.icon, size: 18),
                const SizedBox(width: 8),
                Text(
                  choice.label,
                  style: AppCyberTheme.dataTextStyle(
                    size: 11.6,
                    color: AppCyberTheme.textPrimary,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        child: _StatusPill(label: selected.label, running: false),
      );
    });
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.16)
              : const Color(0xFFEFF8FF))
        : (AppCyberTheme.isCyber
              ? AppCyberTheme.panelBackgroundStrong.withValues(alpha: 0.86)
              : const Color(0xFFFAFBFC));
    final borderColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.9)
              : const Color(0xFF1570EF))
        : (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue.withValues(alpha: 0.35)
              : AppCyberTheme.lineBlue);
    final iconColor = highlighted
        ? (AppCyberTheme.isCyber
              ? AppCyberTheme.neonGreen
              : const Color(0xFF1570EF))
        : (AppCyberTheme.isCyber
              ? AppCyberTheme.electricBlue
              : AppCyberTheme.textMuted);
    final textColor = highlighted
        ? AppCyberTheme.textPrimary
        : AppCyberTheme.textMuted;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: highlighted ? 10 : 8,
        vertical: highlighted ? 6 : 5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
        boxShadow: highlighted && AppCyberTheme.isCyber
            ? [
                BoxShadow(
                  color: AppCyberTheme.electricBlue.withValues(alpha: 0.3),
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
              ]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppCyberTheme.dataTextStyle(
                size: 10.8,
                color: textColor,
                weight: highlighted ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSplitter extends StatelessWidget {
  const _PanelSplitter({required this.axis, required this.onDelta});

  final Axis axis;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    final cursor = isHorizontal
        ? SystemMouseCursors.resizeColumn
        : SystemMouseCursors.resizeRow;

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: isHorizontal
            ? (details) => onDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: !isHorizontal
            ? (details) => onDelta(details.delta.dy)
            : null,
        child: SizedBox(
          width: isHorizontal ? 12 : double.infinity,
          height: isHorizontal ? double.infinity : 12,
          child: Center(
            child: Container(
              width: isHorizontal ? 2 : 44,
              height: isHorizontal ? 44 : 2,
              decoration: AppCyberTheme.isCyber
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppCyberTheme.electricBlue.withValues(alpha: 0.05),
                          AppCyberTheme.electricBlue.withValues(alpha: 0.82),
                          AppCyberTheme.electricBlue.withValues(alpha: 0.05),
                        ],
                        begin: isHorizontal
                            ? Alignment.topCenter
                            : Alignment.centerLeft,
                        end: isHorizontal
                            ? Alignment.bottomCenter
                            : Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppCyberTheme.electricBlue.withValues(
                            alpha: 0.28,
                          ),
                          blurRadius: 12,
                          spreadRadius: -2,
                        ),
                      ],
                    )
                  : BoxDecoration(
                      color: AppCyberTheme.lineBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HudBackdrop extends StatelessWidget {
  const _HudBackdrop();

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppCyberTheme.backdropGradientColors;

    if (!AppCyberTheme.isCyber) {
      return ColoredBox(color: gradientColors.first);
    }

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.55,
              colors: gradientColors,
            ),
          ),
        ),
        Positioned(
          left: -120,
          top: -140,
          child: _GlowOrb(
            size: 320,
            color: AppCyberTheme.electricBlue.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          right: -150,
          bottom: -160,
          child: _GlowOrb(
            size: 340,
            color: AppCyberTheme.neonGreen.withValues(alpha: 0.11),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HudGridPainter(
                color: AppCyberTheme.electricBlue.withValues(alpha: 0.06),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseGlow extends StatefulWidget {
  const _PulseGlow({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<_PulseGlow>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.enabled) {
      _controller?.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _PulseGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;

    if (widget.enabled && !controller.isAnimating) {
      controller.repeat(reverse: true);
    } else if (!widget.enabled && controller.isAnimating) {
      controller.stop();
      controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return AnimatedBuilder(
      animation: _controller ?? const AlwaysStoppedAnimation(0),
      builder: (context, child) {
        final t = Curves.easeInOutSine.transform(_controller?.value ?? 0);
        return DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: AppCyberTheme.electricBlue.withValues(
                  alpha: 0.12 + (t * 0.22),
                ),
                blurRadius: 14 + (t * 18),
                spreadRadius: -8 + (t * 5),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _HudGridPainter extends CustomPainter {
  const _HudGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = Paint()
      ..color = color
      ..strokeWidth = 1;
    final vertical = Paint()
      ..color = color.withValues(alpha: color.a * 0.75)
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), horizontal);
    }
    for (double x = 0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), vertical);
    }
  }

  @override
  bool shouldRepaint(covariant _HudGridPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.color, this.spacing = 10});

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.spacing != spacing;
  }
}

class _CornerBracketPainter extends CustomPainter {
  const _CornerBracketPainter({
    required this.color,
    required this.inset,
    required this.bracketLength,
  });

  final Color color;
  final double inset;
  final double bracketLength;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final right = size.width - inset;
    final bottom = size.height - inset;
    final left = inset;
    final top = inset;
    final l = bracketLength;

    final path = Path()
      ..moveTo(left, top + l)
      ..lineTo(left, top)
      ..lineTo(left + l, top)
      ..moveTo(right - l, top)
      ..lineTo(right, top)
      ..lineTo(right, top + l)
      ..moveTo(left, bottom - l)
      ..lineTo(left, bottom)
      ..lineTo(left + l, bottom)
      ..moveTo(right - l, bottom)
      ..lineTo(right, bottom)
      ..lineTo(right, bottom - l);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.inset != inset ||
        oldDelegate.bracketLength != bracketLength;
  }
}
