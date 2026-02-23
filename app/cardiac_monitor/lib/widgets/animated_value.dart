import 'package:flutter/material.dart';

class AnimatedValue extends StatelessWidget {
  final double value;
  final int decimals;
  final TextStyle? style;
  final Duration duration;
  final String suffix;

  const AnimatedValue({
    super.key,
    required this.value,
    this.decimals = 0,
    this.style,
    this.duration = const Duration(milliseconds: 600),
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        final text = decimals > 0
            ? animatedValue.toStringAsFixed(decimals)
            : animatedValue.round().toString();
        return Text(
          '$text$suffix',
          style: style,
        );
      },
    );
  }
}
