import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Rating badge showing a rating from a specific source (IMDb, TMDB, Site, etc.)
class RatingBadge extends StatelessWidget {
  final double? rating;
  final String? source;
  final bool compact;
  final Color? color;

  const RatingBadge({
    super.key,
    this.rating,
    this.source,
    this.compact = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (rating == null || rating! < 0) {
      return const SizedBox.shrink();
    }

    // Normalize: if > 10, treat as percentage
    final displayRating = rating! > 10
        ? (rating! / 10).clamp(0.0, 10.0)
        : rating!;

    final badgeColor = color ?? _getRatingColor(displayRating);
    final sourceLabel = source?.toUpperCase();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sourceLabel != null && !compact) ...[
            Text(
              sourceLabel,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            displayRating.toStringAsFixed(1),
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getRatingColor(double rating) {
    if (rating >= 7.0) return AppTheme.successColor;
    if (rating >= 5.0) return Colors.orange;
    return AppTheme.errorColor;
  }
}
