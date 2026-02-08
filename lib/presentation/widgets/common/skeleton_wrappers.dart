import 'package:flutter/material.dart';

/// Common skeleton wrappers for consistent loading states
class SkeletonWrappers {
  /// A skeleton for a media card (poster + title + year)
  static Widget mediaCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // Simulated Info Overlay
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 40,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A skeleton for horizontal items (like recommendations)
  static Widget horizontalCard() {
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      child: mediaCard(),
    );
  }

  /// Grid of skeletons
  static Widget grid({
    int count = 6,
    double maxExtent = 180,
    double spacing = 16,
    int? crossAxisCount,
  }) {
    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: crossAxisCount != null && crossAxisCount > 0
          ? SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            )
          : SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxExtent,
              childAspectRatio: 2 / 3,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
            ),
      itemCount: count,
      itemBuilder: (context, index) => mediaCard(),
    );
  }
}
