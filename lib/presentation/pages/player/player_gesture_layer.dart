import 'package:flutter/material.dart';

class PlayerGestureLayer extends StatelessWidget {
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget child;

  const PlayerGestureLayer({
    super.key,
    this.onTap,
    this.onDoubleTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
