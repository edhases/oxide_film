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

/// Single rating display (for cards)
class RatingStar extends StatelessWidget {
  final double? rating;
  final Color? color;
  final bool showValue;

  const RatingStar({super.key, this.rating, this.color, this.showValue = true});

  @override
  Widget build(BuildContext context) {
    if (rating == null) return const SizedBox.shrink();

    final displayColor = color ?? Colors.amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 12, color: displayColor),
          if (showValue) ...[
            const SizedBox(width: 2),
            Text(
              rating!.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Trailer button for playing YouTube trailers
class TrailerButton extends StatelessWidget {
  final String? trailerUrl;
  final VoidCallback? onTap;

  const TrailerButton({super.key, this.trailerUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (trailerUrl == null) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.play_circle_outline),
      label: const Text('Трейлер'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
      ),
    );
  }
}
