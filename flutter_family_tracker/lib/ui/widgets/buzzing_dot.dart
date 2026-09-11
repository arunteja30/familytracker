import 'package:flutter/material.dart';

/// An eye-catching animated buzzing / pulsing unread notification dot.
/// Features a glowing core dot and a smooth repeating ripple wave.
class BuzzingDot extends StatefulWidget {
  final double size;
  final Color color;
  final Color? glowColor;
  final bool isBuzzing;

  const BuzzingDot({
    super.key,
    this.size = 8.0,
    this.color = const Color(0xFFEF4444), // Vibrant Alert Red
    this.glowColor,
    this.isBuzzing = true,
  });

  @override
  State<BuzzingDot> createState() => _BuzzingDotState();
}

class _BuzzingDotState extends State<BuzzingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rippleOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _rippleOpacityAnimation = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    if (widget.isBuzzing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(BuzzingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBuzzing != oldWidget.isBuzzing) {
      if (widget.isBuzzing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isBuzzing) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final rippleScale = 1.0 + (_controller.value * 0.9);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Outer buzzing ripple ring
            Transform.scale(
              scale: rippleScale,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(
                    alpha: _rippleOpacityAnimation.value.clamp(0.0, 1.0),
                  ),
                ),
              ),
            ),
            // Inner pulsing solid core dot with glow
            Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: (widget.glowColor ?? widget.color).withValues(alpha: 0.7),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A wrapper widget that positions a [BuzzingDot] over any child widget (e.g. chat icon).
class BuzzingBadge extends StatelessWidget {
  final Widget child;
  final bool showBadge;
  final double top;
  final double right;
  final double dotSize;
  final Color dotColor;

  const BuzzingBadge({
    super.key,
    required this.child,
    required this.showBadge,
    this.top = -2,
    this.right = -2,
    this.dotSize = 8.0,
    this.dotColor = const Color(0xFFEF4444),
  });

  @override
  Widget build(BuildContext context) {
    if (!showBadge) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: top,
          right: right,
          child: BuzzingDot(
            size: dotSize,
            color: dotColor,
            isBuzzing: showBadge,
          ),
        ),
      ],
    );
  }
}
